import 'dart:io';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _upgradeCode = '3F2504E0-4F89-11D3-9A0C-0305E82C3301';
const ProcessRunner _runner = SystemProcessRunner();

bool get _hasWixl => Process.runSync('which', <String>['wixl']).exitCode == 0;

bool get _hasMsiinfo =>
    Process.runSync('which', <String>['msiinfo']).exitCode == 0;

void _write(String path, String content) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

void main() {
  late Directory root;
  late String stage;
  late String out;

  setUp(() {
    root = Directory.systemTemp.createTempSync('wixl');
    stage = p.join(root.path, 'stage');
    out = p.join(root.path, 'out');
    Directory(out).createSync(recursive: true);
    _write(p.join(stage, 'client.exe'), 'the main binary');
    _write(p.join(stage, 'wintun.dll'), 'a driver');
    _write(p.join(stage, 'data', 'flutter_assets', 'AssetManifest.bin'), 'a');
  });

  tearDown(() => root.deleteSync(recursive: true));

  MsiSpec specWith({
    TargetArch arch = TargetArch.x86_64,
    InstallMode mode = InstallMode.perMachine,
    String productName = 'Example Client',
  }) => MsiSpec(
    bundle: BundleSpec(
      productName: productName,
      manufacturer: 'Example Ltda',
      identifier: 'io.example.client',
      version: AppVersion.parse('2.1.0'),
      mainBinaryName: 'client',
      appDirectory: stage,
      outputDirectory: out,
      installMode: mode,
    ),
    upgradeCode: _upgradeCode,
    arch: arch,
  );

  String sourceFor(MsiSpec spec) => WixlSource.render(
    spec,
    MsiComponentTree.scan(
      appDirectory: spec.bundle.appDirectory,
      upgradeCode: spec.upgradeCode,
    ),
  );

  group('the dialect it writes', () {
    test('should be the v3 schema wixl reads, not the v4 one', () {
      expect(
        sourceFor(specWith()),
        contains('http://schemas.microsoft.com/wix/2006/wi'),
        reason:
            'wixl reads the WiX v3 dialect; the v4 schema the toolset uses is '
            'a different document it will not parse',
      );
      expect(sourceFor(specWith()), contains('<Product'));
    });

    test('a per-machine x64 install should land in ProgramFiles64Folder', () {
      expect(
        WixlSource.rootFolderFor(InstallMode.perMachine, TargetArch.x86_64),
        'ProgramFiles64Folder',
      );
    });

    test('an arm64 install should not claim the 64 bit x86 folder', () {
      expect(
        WixlSource.rootFolderFor(InstallMode.perMachine, TargetArch.arm64),
        'ProgramFilesFolder',
      );
    });

    test('a current-user install must root at LocalAppDataFolder', () {
      expect(
        WixlSource.rootFolderFor(InstallMode.currentUser, TargetArch.x86_64),
        'LocalAppDataFolder',
        reason:
            'a per-user install rooted under Program Files needs elevation it '
            'does not have, and fails at the point of writing files',
      );
      expect(
        sourceFor(specWith(mode: InstallMode.currentUser)),
        contains('InstallScope="perUser"'),
      );
    });

    test('Win64 should be set only for the 64 bit x86 build', () {
      expect(sourceFor(specWith()), contains('Win64="yes"'));
      expect(
        sourceFor(specWith(arch: TargetArch.arm64)),
        isNot(contains('Win64="yes"')),
      );
    });

    test('every component should be referenced by the feature', () {
      final MsiComponentTree tree = MsiComponentTree.scan(
        appDirectory: stage,
        upgradeCode: _upgradeCode,
      );
      final String source = sourceFor(specWith());

      for (final MsiComponent component in tree.components) {
        expect(
          source,
          contains('<ComponentRef Id="${component.id}" />'),
          reason:
              'a component no feature references is a file the installer '
              'carries and never writes',
        );
      }
      expect(tree.components, isNotEmpty);
    });

    test('a name with XML metacharacters should be escaped', () {
      expect(
        sourceFor(specWith(productName: 'Ex & Co <Client>')),
        contains('Ex &amp; Co &lt;Client&gt;'),
      );
    });
  });

  group('the arguments it hands wixl', () {
    test('should name the architecture wixl understands', () {
      expect(
        const WixlTool(runner: _runner).argumentsFor(
          sourceFile: '/t/p.wxs',
          outputFile: '/t/out.msi',
          arch: TargetArch.x86_64,
        ),
        <String>['-a', 'x64', '-o', '/t/out.msi', '/t/p.wxs'],
      );
    });

    test('an absent source should be refused before wixl runs', () async {
      await expectLater(
        const WixlTool(runner: _runner).build(
          sourceFile: '/t/missing.wxs',
          outputFile: '/t/out.msi',
          arch: TargetArch.x86_64,
        ),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.message,
            'message',
            contains('no wxs source'),
          ),
        ),
      );
    });
  });

  group('against the real wixl, on this machine', () {
    test(
      'a generated source should compile into an installer',
      () async {
        if (!_hasWixl) {
          markTestSkipped('wixl comes with msitools');
          return;
        }

        final MsiSpec spec = specWith();
        final String source = p.join(stage, 'installer.wxs');
        File(source).writeAsStringSync(sourceFor(spec));
        final String msi = p.join(out, 'client.msi');

        await const WixlTool(
          runner: _runner,
        ).build(sourceFile: source, outputFile: msi, arch: TargetArch.x86_64);

        final List<int> header = File(msi).readAsBytesSync().take(8).toList();
        expect(
          header,
          <int>[0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1],
          reason:
              'an MSI is an OLE2 compound document, and the WiX toolset cannot '
              'write one off Windows because it binds through msi.dll',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'the installer should carry the product it was told to',
      () async {
        if (!_hasWixl || !_hasMsiinfo) {
          markTestSkipped('wixl and msiinfo come with msitools');
          return;
        }

        final MsiSpec spec = specWith();
        final String source = p.join(stage, 'installer.wxs');
        File(source).writeAsStringSync(sourceFor(spec));
        final String msi = p.join(out, 'client.msi');

        await const WixlTool(
          runner: _runner,
        ).build(sourceFile: source, outputFile: msi, arch: TargetArch.x86_64);

        final String properties = Process.runSync('msiinfo', <String>[
          'export',
          msi,
          'Property',
        ]).stdout.toString();

        expect(properties, contains('Example Client'));
        expect(properties, contains('Example Ltda'));
        expect(properties, contains('2.1.0'));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'the embedded cab should hold every staged file',
      () async {
        if (!_hasWixl || !_hasMsiinfo) {
          markTestSkipped('wixl and msiinfo come with msitools');
          return;
        }

        final MsiSpec spec = specWith();
        final String source = p.join(stage, 'installer.wxs');
        File(source).writeAsStringSync(sourceFor(spec));
        final String msi = p.join(out, 'client.msi');

        await const WixlTool(
          runner: _runner,
        ).build(sourceFile: source, outputFile: msi, arch: TargetArch.x86_64);

        final Directory extracted = Directory(p.join(root.path, 'extracted'));
        Process.runSync('msiextract', <String>[
          '-C',
          extracted.path,
          msi,
        ], workingDirectory: root.path);

        final List<String> files = extracted
            .listSync(recursive: true)
            .whereType<File>()
            .map((File file) => p.basename(file.path))
            .toList();

        expect(files, contains('client.exe'));
        expect(
          files,
          contains('wintun.dll'),
          reason:
              'a driver left out of the cab is an installer that completes and '
              'produces an application that cannot open a tunnel',
        );
        expect(files, contains('AssetManifest.bin'));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  _backendGroup();
}

void _backendGroup() {
  group('which backend builds the MSI', () {
    test('Windows should get the WiX toolset', () {
      expect(MsiBackend.forHost(onWindows: true), MsiBackend.wix);
      expect(MsiBackend.wix.needsWindows, true);
    });

    test('anywhere else should get wixl', () {
      expect(
        MsiBackend.forHost(onWindows: false),
        MsiBackend.wixl,
        reason:
            'wix binds through msi.dll and cannot write a database off '
            'Windows; wixl writes it directly',
      );
      expect(MsiBackend.wixl.needsWindows, false);
    });

    test('each backend should name the executable it drives', () {
      expect(MsiBackend.wix.executable, 'wix');
      expect(MsiBackend.wixl.executable, 'wixl');
    });
  });
}
