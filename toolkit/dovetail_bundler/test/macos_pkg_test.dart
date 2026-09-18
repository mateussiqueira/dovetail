import 'dart:io';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final class _Recording implements ProcessRunner {
  final List<List<String>> calls = <List<String>>[];

  /// O corpo do postinstall lido enquanto o scratch ainda existe: o bundler o
  /// apaga no `finally`, e depois nao ha o que ler.
  String? postinstallBody;

  @override
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdin,
    Duration? timeout,
  }) async {
    calls.add(<String>[executable, ...arguments]);
    if (executable == 'pkgbuild') {
      final int scripts = arguments.indexOf('--scripts');
      if (scripts != -1) {
        postinstallBody = File(
          p.join(arguments[scripts + 1], 'postinstall'),
        ).readAsStringSync();
      }
    }
    // O pkgbuild e o productbuild de verdade nao rodam; os arquivos que eles
    // escreveriam sao escritos aqui para as checagens de existencia passarem.
    if (executable == 'pkgbuild' || executable == 'productbuild') {
      File(arguments.last).writeAsStringSync('pkg bytes');
    }
    return const ProcessOutcome(exitCode: 0, stdout: '', stderr: '');
  }
}

BundleSpec _specFor(String appDirectory, String out) => BundleSpec(
  productName: 'Demo',
  manufacturer: 'M',
  identifier: 'com.example.demo',
  version: AppVersion.parse('4.2.0'),
  mainBinaryName: 'demo_app',
  appDirectory: appDirectory,
  outputDirectory: out,
);

LaunchDaemon _daemon() =>
    LaunchDaemon(label: 'com.example.demo.helper', program: 'demo-helper');

MacosServiceScripts _scriptsFor(LaunchDaemon daemon) => MacosServiceScripts(
  daemon: daemon,
  identifier: 'com.example.demo',
  applicationPath: '/Applications/Demo.app',
);

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('dovetail_pkg'));
  tearDown(() => root.deleteSync(recursive: true));

  String appWithHelper() {
    final String app = p.join(root.path, 'Demo.app');
    File(p.join(app, 'Contents', 'Info.plist'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '<plist version="1.0"><dict>'
        '<key>LSMinimumSystemVersion</key><string>11.0</string>'
        '</dict></plist>',
      );
    File(p.join(app, 'Contents', 'MacOS', 'demo-helper'))
      ..createSync(recursive: true)
      ..writeAsStringSync('mach-o bytes');
    return app;
  }

  group('the launchd property list', () {
    test('points at the installed path, not into the bundle', () {
      final String plist = _daemon().render();
      expect(plist, contains('<key>Label</key>'));
      expect(plist, contains('<string>com.example.demo.helper</string>'));
      expect(
        plist,
        contains('<string>/Library/PrivilegedHelperTools/com.example.demo.helper</string>'),
      );
      expect(plist, contains('<key>RunAtLoad</key>'));
      expect(plist, contains('<key>KeepAlive</key>'));
      expect(plist, contains('Interactive'));
      // Um daemon do sistema nao usa BundleProgram: ele nao esta num bundle.
      expect(plist, isNot(contains('BundleProgram')));
    });

    test('omits KeepAlive when it is false, and refuses neither', () {
      expect(
        LaunchDaemon(
          label: 'com.example.demo.helper',
          program: 'demo-helper',
          keepAlive: false,
        ).render(),
        isNot(contains('KeepAlive')),
      );
      expect(
        () => LaunchDaemon(
          label: 'com.example.demo.helper',
          program: 'demo-helper',
          runAtLoad: false,
          keepAlive: false,
        ),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('escapes the XML of an argument instead of breaking the plist', () {
      final String plist = LaunchDaemon(
        label: 'com.example.demo.helper',
        program: 'demo-helper',
        arguments: <String>['--mode', 'a&b'],
      ).render();
      expect(plist, contains('<string>a&amp;b</string>'));
    });

    test('refuses a label outside the reverse-dns shape', () {
      expect(
        () => LaunchDaemon(label: 'demo helper', program: 'demo-helper'),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('refuses a program that is a path or carries a quote', () {
      expect(
        () => LaunchDaemon(
          label: 'com.example.demo.helper',
          program: 'Contents/MacOS/demo-helper',
        ),
        throwsA(isA<BundleFailure>()),
      );
      expect(
        () => LaunchDaemon(
          label: 'com.example.demo.helper',
          program: "demo'helper",
        ),
        throwsA(isA<BundleFailure>()),
      );
    });
  });

  group('the scripts the package runs', () {
    test('the postinstall boots out first, then installs and bootstraps', () {
      final MacosServiceScripts scripts = _scriptsFor(_daemon());
      final String body = scripts.postinstall;
      final int bootout = body.indexOf('launchctl bootout');
      final int install = body.indexOf('install -o root -g wheel -m 0544');
      final int bootstrap = body.indexOf('launchctl bootstrap');
      expect(bootout, greaterThanOrEqualTo(0));
      expect(install, greaterThan(bootout));
      expect(bootstrap, greaterThan(install));
      expect(
        body,
        contains(
          "'/Applications/Demo.app/Contents/MacOS/demo-helper' "
          "'/Library/PrivilegedHelperTools/com.example.demo.helper'",
        ),
      );
      const String plistPath =
          '/Library/LaunchDaemons/com.example.demo.helper.plist';
      expect(body, contains("chown root:wheel '$plistPath'"));
      expect(body, contains("chmod 0644 '$plistPath'"));
      // Escreve o desinstalador no disco, porque o pkg nao tem um.
      expect(
        body,
        contains(
          "cat > '/Library/Application Support/com.example.demo/uninstall'",
        ),
      );
      // Insiste ate cinco vezes, e larga o plist antes de falhar.
      expect(body, contains('_dovetail_attempt in 1 2 3 4 5'));
      expect(
        body,
        contains(
          "rm -f '/Library/LaunchDaemons/com.example.demo.helper.plist'",
        ),
      );
    });

    test('the uninstaller undoes it in reverse and forgets the receipt', () {
      final String body = _scriptsFor(_daemon()).uninstall;
      final int bootout = body.indexOf('launchctl bootout');
      final int plist = body.indexOf(
        "rm -f '/Library/LaunchDaemons/com.example.demo.helper.plist'",
      );
      final int binary = body.indexOf(
        "rm -f '/Library/PrivilegedHelperTools/com.example.demo.helper'",
      );
      expect(bootout, greaterThanOrEqualTo(0));
      expect(plist, greaterThan(bootout));
      expect(binary, greaterThan(plist));
      expect(body, contains("pkgutil --forget 'com.example.demo'"));
      // O diretorio de helpers e compartilhado: so o binario deste produto sai.
      expect(
        body,
        isNot(contains("rmdir '/Library/PrivilegedHelperTools'")),
      );
      expect(
        body,
        contains(
          "rm -f '/Library/Application Support/com.example.demo/uninstall'",
        ),
      );
    });

    test('refuses a purge path that is relative or too close to the root', () {
      expect(
        () => MacosServiceScripts(
          daemon: _daemon(),
          identifier: 'com.example.demo',
          applicationPath: '/Applications/Demo.app',
          purgePaths: <String>['var/lib/demo'],
        ),
        throwsA(isA<BundleFailure>()),
      );
      expect(
        () => MacosServiceScripts(
          daemon: _daemon(),
          identifier: 'com.example.demo',
          applicationPath: '/Applications/Demo.app',
          purgePaths: <String>['/tmp'],
        ),
        throwsA(isA<BundleFailure>()),
      );
    });
  });

  group('the pkg bundler', () {
    test('names the file with the architecture suffix the dmg uses', () {
      final BundleSpec spec = _specFor('/x/Demo.app', root.path);
      expect(
        const PkgBundler(runner: SystemProcessRunner()).fileNameFor(spec),
        'demo_app_4.2.0.pkg',
      );
      expect(
        const PkgBundler(
          runner: SystemProcessRunner(),
          requiredArchitectures: <TargetArch>{TargetArch.arm64},
        ).fileNameFor(spec),
        'demo_app_4.2.0_arm64.pkg',
      );
      expect(
        const PkgBundler(
          runner: SystemProcessRunner(),
          requiredArchitectures: <TargetArch>{
            TargetArch.arm64,
            TargetArch.x86_64,
          },
        ).fileNameFor(spec),
        'demo_app_4.2.0_universal.pkg',
      );
    });

    test('asks pkgbuild for the app at /Applications, then wraps it', () async {
      final _Recording recording = _Recording();
      final String app = appWithHelper();
      final LaunchDaemon daemon = _daemon();
      final PkgBundler bundler = PkgBundler(
        runner: recording,
        daemon: daemon,
        scripts: _scriptsFor(daemon),
      );

      final String produced = await bundler.bundle(_specFor(app, root.path));

      expect(produced, p.join(root.path, 'demo_app_4.2.0.pkg'));
      final List<String> pkgbuild = recording.calls.firstWhere(
        (List<String> call) => call.first == 'pkgbuild',
      );
      expect(
        pkgbuild,
        containsAllInOrder(<String>[
          '--root',
          app,
          '--identifier',
          'com.example.demo',
          '--version',
          '4.2.0',
          '--install-location',
          '/Applications/Demo.app',
          '--scripts',
        ]),
      );
      final List<String> productbuild = recording.calls.firstWhere(
        (List<String> call) => call.first == 'productbuild',
      );
      expect(productbuild.first, 'productbuild');
      expect(productbuild[1], '--package');
      // O postinstall viaja executavel: um script que o instalador nao
      // consegue rodar aborta a instalacao inteira.
      expect(
        recording.calls.any(
          (List<String> call) =>
              call.first == 'chmod' &&
              call.contains('0755') &&
              call.last.endsWith('postinstall'),
        ),
        isTrue,
      );
      expect(recording.postinstallBody, contains('launchctl bootstrap'));
    });

    test('a half-configured service is refused', () {
      expect(
        () => PkgBundler(
          runner: _Recording(),
          daemon: _daemon(),
        ).bundle(_specFor(appWithHelper(), root.path)),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('a helper the bundle does not carry is refused before pkgbuild', () {
      final Directory empty = Directory(p.join(root.path, 'Empty.app'))
        ..createSync();
      final LaunchDaemon daemon = _daemon();
      expect(
        () => PkgBundler(
          runner: _Recording(),
          daemon: daemon,
          scripts: _scriptsFor(daemon),
        ).bundle(_specFor(empty.path, root.path)),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('a dmg-only directory is refused, naming what it wants', () {
      expect(
        () => const PkgBundler(
          runner: SystemProcessRunner(),
        ).bundle(_specFor(p.join(root.path, 'Demo'), root.path)),
        throwsA(isA<BundleFailure>()),
      );
    });
  });
}
