import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:test/test.dart';

BundleSpec specWith({
  String productName = 'Example',
  String? hooks = '/tmp/hooks.nsh',
  InstallMode installMode = InstallMode.perMachine,
  String version = '1.2.3+47',
  List<StagedFile> extraFiles = const <StagedFile>[],
  String? homepage,
}) => BundleSpec(
  productName: productName,
  manufacturer: 'Example Ltd',
  identifier: 'com.example.app',
  version: AppVersion.parse(version),
  mainBinaryName: 'example',
  appDirectory: '/tmp/app',
  outputDirectory: '/tmp/out',
  installMode: installMode,
  installerHooks: hooks,
  extraFiles: extraFiles,
  homepage: homepage,
);

int lineOf(String script, Pattern needle) {
  final List<String> lines = script.split('\n');
  for (int index = 0; index < lines.length; index++) {
    if (lines[index].contains(needle)) {
      return index;
    }
  }
  return -1;
}

String renderFor(BundleSpec spec, [TargetArch arch = TargetArch.x86_64]) =>
    NsisScript.render(spec, arch);

void main() {
  test('addplugindir should come before every include', () {
    final String sut = renderFor(specWith());

    final int plugins = lineOf(sut, '!addplugindir');
    final List<int> includes = <int>[];
    final List<String> lines = sut.split('\n');
    for (int index = 0; index < lines.length; index++) {
      if (lines[index].startsWith('!include')) {
        includes.add(index);
      }
    }

    expect(plugins, greaterThan(-1));
    expect(includes, isNotEmpty);
    expect(
      plugins,
      lessThan(includes.first),
      reason:
          'a plugin command before !addplugindir makes makensis fall back to '
          'the unsigned toolset DLLs without saying so',
    );
  });

  test(
    'the check for a running app should follow the preinstall hook at once',
    () {
      final String sut = renderFor(specWith());

      final int hook = lineOf(sut, '!insertmacro NSIS_HOOK_PREINSTALL');
      final int check = lineOf(sut, '!insertmacro CheckIfAppIsRunning');

      expect(hook, greaterThan(-1));
      expect(check, hook + 2, reason: 'only the !endif may sit between them');
    },
  );

  test('all four hook points should be emitted and guarded', () {
    final String sut = renderFor(specWith());

    for (final String hook in <String>[
      'NSIS_HOOK_PREINSTALL',
      'NSIS_HOOK_POSTINSTALL',
      'NSIS_HOOK_PREUNINSTALL',
      'NSIS_HOOK_POSTUNINSTALL',
    ]) {
      expect(sut, contains('!ifmacrodef $hook'), reason: hook);
      expect(sut, contains('!insertmacro $hook'), reason: hook);
    }
  });

  test(
    'the postinstall hook should be the last thing in the install section',
    () {
      final String sut = renderFor(specWith());

      final int hook = lineOf(sut, '!insertmacro NSIS_HOOK_POSTINSTALL');
      final int sectionEnd = lineOf(sut, 'SectionEnd');

      expect(hook, lessThan(sectionEnd));
      expect(sectionEnd, hook + 2);
    },
  );

  test('the hooks file should be included before the sections that use it', () {
    final String sut = renderFor(specWith(hooks: '/tmp/hooks.nsh'));

    expect(
      lineOf(sut, '!include "/tmp/hooks.nsh"'),
      lessThan(lineOf(sut, 'Section Install')),
    );
  });

  test('a spec without hooks should still compile the guards', () {
    final String sut = renderFor(specWith(hooks: null));

    expect(sut, isNot(contains('hooks.nsh')));
    expect(sut, contains('!ifmacrodef NSIS_HOOK_PREINSTALL'));
  });

  test('perMachine should ask for admin and write to Program Files', () {
    final String sut = renderFor(specWith(installMode: InstallMode.perMachine));

    expect(sut, contains('RequestExecutionLevel admin'));
    expect(sut, contains(r'InstallDir "$PROGRAMFILES64\${PRODUCTNAME}"'));
    expect(sut, contains('SetShellVarContext all'));
  });

  test('currentUser should not ask for admin', () {
    final String sut = renderFor(
      specWith(installMode: InstallMode.currentUser),
    );

    expect(sut, contains('RequestExecutionLevel user'));
    expect(sut, contains(r'InstallDir "$LOCALAPPDATA\${PRODUCTNAME}"'));
    expect(sut, contains('SetShellVarContext current'));
  });

  test('the windows file version should carry the build number', () {
    final String sut = renderFor(specWith(version: '1.2.3+47'));

    expect(sut, contains('VIProductVersion "1.2.3.47"'));
    expect(sut, contains('!define VERSION "1.2.3"'));
  });

  test('a product name with a quote should not break the script', () {
    final String sut = renderFor(specWith(productName: 'My "App"'));

    expect(sut, contains(r'!define PRODUCTNAME "My $\"App$\""'));
  });

  test('the uninstall section should remove both registry keys', () {
    final String sut = renderFor(specWith());

    expect(sut, contains(r'DeleteRegKey SHCTX "${UNINSTKEY}"'));
    expect(sut, contains(r'DeleteRegKey SHCTX "${MANUPRODUCTKEY}"'));
  });

  test(
    'the install section should record the binary name for a later upgrade',
    () {
      final String sut = renderFor(specWith());

      expect(
        sut,
        contains(r'"MainBinaryName" "${MAINBINARYNAME}.exe"'),
        reason:
            'an upgrade that renames the binary needs the old name to clean',
      );
    },
  );

  test('extra files should be staged at their destination', () {
    final String sut = renderFor(
      specWith(
        extraFiles: const <StagedFile>[
          StagedFile(source: '/tmp/wintun.dll', destination: 'vendor'),
        ],
      ),
    );

    expect(sut, contains(r'SetOutPath "$INSTDIR\vendor"'));
    expect(sut, contains('File "/tmp/wintun.dll"'));
  });

  test('a homepage should reach Add or Remove Programs', () {
    final String sut = renderFor(specWith(homepage: 'https://example.com'));

    expect(sut, contains('"URLInfoAbout" "https://example.com"'));
  });

  test('no homepage should leave the key out entirely', () {
    expect(renderFor(specWith()), isNot(contains('URLInfoAbout')));
  });

  group('the architecture in the artefact name', () {
    test('two architectures should not write the same installer', () {
      final BundleSpec spec = specWith();

      expect(
        spec.installerFileNameFor(TargetArch.x86_64),
        isNot(spec.installerFileNameFor(TargetArch.arm64)),
        reason:
            'both used to be <name>_<version>_setup.exe, so publishing the '
            'pair into one directory silently kept whichever was copied last',
      );
    });

    test('the name should carry the spelling Windows installers use', () {
      final BundleSpec spec = specWith();

      expect(spec.installerFileNameFor(TargetArch.x86_64), contains('_x64_'));
      expect(spec.installerFileNameFor(TargetArch.arm64), contains('_arm64_'));
    });

    test('the script should name the file it is asked to write', () {
      final BundleSpec spec = specWith();

      expect(
        renderFor(spec, TargetArch.arm64),
        contains('OutFile "${spec.installerFileNameFor(TargetArch.arm64)}"'),
      );
    });
  });
}
