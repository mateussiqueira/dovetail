import 'dart:io';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _upgradeCode = '5C9E1E0A-3B2D-4A11-9F0E-7D6C5B4A3928';

void main() {
  late Directory root;
  late String stage;
  late String out;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_msi');
    stage = p.join(root.path, 'stage');
    out = p.join(root.path, 'out');
    _write(p.join(stage, 'client.exe'), 'binary');
    _write(p.join(stage, 'helper.exe'), 'binary');
    _write(p.join(stage, 'wintun.dll'), 'driver');
    _write(p.join(stage, 'data', 'flutter_assets', 'AssetManifest.bin'), 'a');
    _write(p.join(stage, 'data', 'icudtl.dat'), 'i');
  });

  tearDown(() => root.deleteSync(recursive: true));

  MsiSpec buildSpec({
    List<MsiPrivilegedStep> steps = const <MsiPrivilegedStep>[],
    String version = '2.1.0',
    TargetArch arch = TargetArch.x86_64,
    InstallMode mode = InstallMode.perMachine,
    List<String> conflicts = const <String>[],
  }) => MsiSpec(
    bundle: BundleSpec(
      productName: 'Example Client',
      manufacturer: 'Example Ltda',
      identifier: 'io.example.client',
      version: AppVersion.parse(version),
      mainBinaryName: 'client',
      appDirectory: stage,
      outputDirectory: out,
      installMode: mode,
    ),
    upgradeCode: _upgradeCode,
    arch: arch,
    steps: steps,
    conflictingRegistryKeys: conflicts,
  );

  group('MsiVersion', () {
    test('should carry only the three fields the MSI compares', () {
      expect(MsiVersion.of(AppVersion.parse('2.1.0+904')), '2.1.0');
    });

    test('should refuse a major above the single byte the MSI stores', () {
      expect(
        () => MsiVersion.of(AppVersion.parse('256.0.0')),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('should refuse a patch above the two bytes the MSI stores', () {
      expect(
        () => MsiVersion.of(AppVersion.parse('1.0.65536')),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('should accept the exact ceiling', () {
      expect(MsiVersion.of(AppVersion.parse('255.255.65535')), '255.255.65535');
    });

    test('two versions differing only in build should compare equal', () {
      expect(
        MsiVersion.comparesEqual(
          AppVersion.parse('2.1.0+1'),
          AppVersion.parse('2.1.0+9999'),
        ),
        true,
      );
    });
  });

  group('MsiComponentGuid', () {
    test('the same path should always produce the same guid', () {
      expect(
        MsiComponentGuid.forPath(
          upgradeCode: _upgradeCode,
          relativePath: 'wintun.dll',
        ),
        MsiComponentGuid.forPath(
          upgradeCode: '{5c9e1e0a-3b2d-4a11-9f0e-7d6c5b4a3928}',
          relativePath: 'wintun.dll',
        ),
      );
    });

    test('the golden values should never move', () {
      expect(
        MsiComponentGuid.forPath(
          upgradeCode: _upgradeCode,
          relativePath: 'wintun.dll',
        ),
        '60CC3800-E91F-533B-B7F9-7E15F16BA4B7',
      );
      expect(
        MsiComponentGuid.forPath(
          upgradeCode: _upgradeCode,
          relativePath: 'data/icudtl.dat',
        ),
        '774E7A20-9183-5E83-870C-D311D394E6C9',
      );
    });

    test('should agree with the rfc 4122 reference vector', () {
      expect(
        MsiComponentGuid.forPath(
          upgradeCode: '6ba7b810-9dad-11d1-80b4-00c04fd430c8',
          relativePath: 'python.org',
        ),
        '886313E1-3B8A-5372-9B90-0C9AEE199E5D',
      );
    });

    test('should be a version 5 uuid with the rfc variant bits', () {
      final String guid = MsiComponentGuid.forPath(
        upgradeCode: _upgradeCode,
        relativePath: 'client.exe',
      );
      expect(guid.split('-')[2][0], '5');
      expect('89AB'.contains(guid.split('-')[3][0]), true);
    });

    test('a different upgrade code should produce a different guid', () {
      expect(
        MsiComponentGuid.forPath(
          upgradeCode: '00000000-0000-4000-8000-000000000001',
          relativePath: 'wintun.dll',
        ),
        isNot(
          MsiComponentGuid.forPath(
            upgradeCode: _upgradeCode,
            relativePath: 'wintun.dll',
          ),
        ),
      );
    });

    test('a separator should not change the identity of a path', () {
      expect(
        MsiComponentGuid.forPath(
          upgradeCode: _upgradeCode,
          relativePath: r'data\icudtl.dat',
        ),
        MsiComponentGuid.forPath(
          upgradeCode: _upgradeCode,
          relativePath: 'data/icudtl.dat',
        ),
      );
    });

    test('should refuse an upgrade code that is not a guid', () {
      expect(
        () => MsiComponentGuid.forPath(
          upgradeCode: 'not-a-guid',
          relativePath: 'a',
        ),
        throwsA(isA<BundleFailure>()),
      );
    });
  });

  group('WixText', () {
    test('should escape the five xml entities in an attribute', () {
      expect(
        WixText.attribute(<String>['&', '<', '>', '"', "'"].join()),
        '&amp;&lt;&gt;&quot;&apos;',
      );
    });

    test('an identifier should never start with a digit', () {
      expect(WixText.identifier('9lives').startsWith('id'), true);
    });

    test('an identifier should replace every unsafe character', () {
      expect(WixText.identifier('a b-c/d'), 'a_b_c_d');
    });

    test('a long identifier should stay inside the limit and stay unique', () {
      final String a = WixText.identifier('x' * 90 + 'one');
      final String b = WixText.identifier('x' * 90 + 'two');
      expect(a.length, lessThanOrEqualTo(WixText.identifierLimit));
      expect(a, isNot(b));
    });
  });

  group('MsiComponentTree', () {
    test('should hold one component per staged file', () {
      final MsiComponentTree tree = MsiBundler(
        tool: WixTool(runner: _StubRunner()),
      ).scan(buildSpec());
      expect(tree.components, hasLength(5));
    });

    test('every component should be its own key path', () {
      final MsiComponentTree tree = MsiBundler(
        tool: WixTool(runner: _StubRunner()),
      ).scan(buildSpec());
      expect(
        tree.components.map((MsiComponent c) => c.id).toSet(),
        hasLength(tree.components.length),
      );
    });

    test('should rebuild the nested directories it found', () {
      final MsiComponentTree tree = MsiBundler(
        tool: WixTool(runner: _StubRunner()),
      ).scan(buildSpec());
      expect(
        tree.directories.map((MsiDirectory d) => d.relativePath),
        containsAll(<String>['data', 'data/flutter_assets']),
      );
      expect(
        tree.childrenOf('data').single.relativePath,
        'data/flutter_assets',
      );
    });

    test('should refuse a staged tree that does not exist', () {
      expect(
        () => MsiComponentTree.scan(
          appDirectory: p.join(root.path, 'absent'),
          upgradeCode: _upgradeCode,
        ),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('should refuse an empty staged tree', () {
      final String empty = p.join(root.path, 'empty');
      Directory(empty).createSync();
      expect(
        () => MsiComponentTree.scan(
          appDirectory: empty,
          upgradeCode: _upgradeCode,
        ),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('should carry the extra files the spec staged', () {
      final String extra = p.join(root.path, 'polkit.policy');
      _write(extra, 'x');
      final MsiComponentTree tree = MsiComponentTree.scan(
        appDirectory: stage,
        upgradeCode: _upgradeCode,
        extraFiles: <StagedFile>[
          StagedFile(source: extra, destination: 'config/policy.xml'),
        ],
      );
      expect(tree.componentFor('config/policy.xml'), isNotNull);
    });
  });

  group('WixSource', () {
    String render({
      List<MsiPrivilegedStep> steps = const <MsiPrivilegedStep>[],
      List<String> conflicts = const <String>[],
      TargetArch arch = TargetArch.x86_64,
      InstallMode mode = InstallMode.perMachine,
    }) {
      final MsiSpec spec = buildSpec(
        steps: steps,
        conflicts: conflicts,
        arch: arch,
        mode: mode,
      );
      return WixSource.render(
        spec,
        MsiBundler(tool: WixTool(runner: _StubRunner())).scan(spec),
      );
    }

    test('should declare the v4 schema and the version the MSI compares', () {
      final String source = render();
      expect(source, contains('xmlns="${WixSource.schema}"'));
      expect(source, contains('Version="2.1.0"'));
      expect(source, contains('UpgradeCode="$_upgradeCode"'));
    });

    test('should reference every component in the feature', () {
      final String source = render();
      final MsiSpec spec = buildSpec();
      final MsiComponentTree tree = MsiBundler(
        tool: WixTool(runner: _StubRunner()),
      ).scan(spec);
      for (final MsiComponent component in tree.components) {
        expect(source, contains('<ComponentRef Id="${component.id}" />'));
      }
    });

    test('a per-machine package should say so', () {
      expect(render(), contains('Scope="perMachine"'));
      expect(
        render(mode: InstallMode.currentUser),
        contains('Scope="perUser"'),
      );
    });

    test('should refuse a downgrade unless the spec allows it', () {
      expect(render(), contains('AllowDowngrades="no"'));
      expect(render(), contains('DowngradeErrorMessage='));
    });

    test('a foreign installation should abort the install, not warn', () {
      final String source = render(
        conflicts: <String>[
          r'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Example',
        ],
      );
      expect(source, contains('<Launch'));
      expect(source, contains('Condition="NOT FOREIGNINSTALL0"'));
      expect(source, contains('Uninstall it first'));
    });

    test('should schedule the rollback action before the work it undoes', () {
      final String source = render(
        steps: <MsiPrivilegedStep>[
          const MsiPrivilegedStep(
            id: 'InstallService',
            phase: MsiPhase.afterInstallFiles,
            relativeExecutable: 'helper.exe',
            arguments: <String>['--install-service'],
          ),
          const MsiPrivilegedStep(
            id: 'CleanupService',
            phase: MsiPhase.afterInstallFiles,
            relativeExecutable: 'helper.exe',
            arguments: <String>['--cleanup'],
            rollbackFor: 'InstallService',
            fatalOnFailure: false,
          ),
        ],
      );
      expect(
        source.indexOf('Id="CleanupService"'),
        lessThan(source.indexOf('Id="InstallService"')),
      );
      expect(source, contains('Execute="rollback"'));
      expect(source, contains('Execute="deferred"'));
      expect(source, contains('Impersonate="no"'));
      expect(source, contains('Return="ignore"'));
    });

    test('a privileged step should run from the file it installs', () {
      final String source = render(
        steps: <MsiPrivilegedStep>[
          const MsiPrivilegedStep(
            id: 'InstallService',
            phase: MsiPhase.afterInstallFiles,
            relativeExecutable: 'helper.exe',
            arguments: <String>['--install-service'],
          ),
        ],
      );
      expect(source, contains('FileRef="file.helper.exe"'));
      expect(source, contains('ExeCommand="--install-service"'));
      expect(source, contains('After="InstallFiles"'));
    });

    test('should refuse a step pointing at a file the tree does not hold', () {
      expect(
        () => render(
          steps: <MsiPrivilegedStep>[
            const MsiPrivilegedStep(
              id: 'Ghost',
              phase: MsiPhase.afterInstallFiles,
              relativeExecutable: 'absent.exe',
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('should place the tree under the 64 bit program files', () {
      expect(
        render(),
        contains('<StandardDirectory Id="ProgramFiles64Folder">'),
      );
      expect(
        render(arch: TargetArch.arm64),
        contains('<StandardDirectory Id="ProgramFiles64Folder">'),
      );
    });

    test('a per-user package should install where a user can write', () {
      final String source = render(mode: InstallMode.currentUser);
      expect(source, contains('<StandardDirectory Id="LocalAppDataFolder">'));
      expect(source, contains('Scope="perUser"'));
      expect(
        source,
        isNot(contains('ProgramFiles64Folder')),
        reason:
            'the NSIS path already sends currentUser to LOCALAPPDATA; an MSI '
            'that writes Program Files without elevation fails the install',
      );
    });

    test('the root should follow the scope, both ways', () {
      expect(
        render().contains('ProgramFiles64Folder') &&
            render(
              mode: InstallMode.currentUser,
            ).contains('LocalAppDataFolder'),
        true,
      );
    });

    test('a file source should be a windows path under the stage define', () {
      expect(
        render(),
        contains(
          r'Source="$(var.StageDir)\data\flutter_assets\AssetManifest.bin"',
        ),
      );
    });

    test('the same spec should render byte for byte the same source', () {
      expect(render(), render());
    });
  });

  group('MsiSpec', () {
    test('should refuse two steps with the same id', () {
      expect(
        () => buildSpec(
          steps: <MsiPrivilegedStep>[
            const MsiPrivilegedStep(
              id: 'Same',
              phase: MsiPhase.afterInstallFiles,
              relativeExecutable: 'helper.exe',
            ),
            const MsiPrivilegedStep(
              id: 'Same',
              phase: MsiPhase.beforeRemoveFiles,
              relativeExecutable: 'helper.exe',
            ),
          ],
        ),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('should refuse a rollback for a step nobody declared', () {
      expect(
        () => buildSpec(
          steps: <MsiPrivilegedStep>[
            const MsiPrivilegedStep(
              id: 'Cleanup',
              phase: MsiPhase.afterInstallFiles,
              relativeExecutable: 'helper.exe',
              rollbackFor: 'NeverDeclared',
            ),
          ],
        ),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('should refuse a privileged step in a per-user package', () {
      expect(
        () => buildSpec(
          mode: InstallMode.currentUser,
          steps: <MsiPrivilegedStep>[
            const MsiPrivilegedStep(
              id: 'InstallService',
              phase: MsiPhase.afterInstallFiles,
              relativeExecutable: 'helper.exe',
            ),
          ],
        ),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('the file name should carry the version and the architecture', () {
      expect(buildSpec().msiFileName, 'client_2.1.0_x64.msi');
      expect(
        buildSpec(arch: TargetArch.arm64).msiFileName,
        'client_2.1.0_arm64.msi',
      );
    });

    test('should refuse a version the MSI cannot compare', () {
      expect(
        () => buildSpec(version: '300.0.0').productVersion,
        throwsA(isA<BundleFailure>()),
      );
    });
  });

  group('TargetArch', () {
    test('should read the names a toolchain actually prints', () {
      expect(TargetArch.parse('AMD64'), TargetArch.x86_64);
      expect(TargetArch.parse('x86_64'), TargetArch.x86_64);
      expect(TargetArch.parse('aarch64'), TargetArch.arm64);
    });

    test('should refuse a target it does not build', () {
      expect(() => TargetArch.parse('x86'), throwsA(isA<BundleFailure>()));
    });
  });

  group('MsiBundler', () {
    test('writeSource should write the wxs anywhere, including here', () {
      final String written = MsiBundler(
        tool: WixTool(runner: _StubRunner()),
      ).writeSource(buildSpec());
      expect(File(written).readAsStringSync(), contains('<Wix'));
    });

    test('bundle should refuse to pretend it can cross-build', () async {
      if (Platform.isWindows) {
        return;
      }
      await expectLater(
        MsiBundler(tool: WixTool(runner: _StubRunner())).bundle(buildSpec()),
        throwsA(isA<BundleFailure>()),
      );
    });
  });

  group('WixTool', () {
    test('should accept the eula the wix binaries now demand', () async {
      final _StubRunner runner = _StubRunner();
      await WixTool(runner: runner).build(
        sourceFile: 'a.wxs',
        outputFile: 'a.msi',
        arch: TargetArch.x86_64,
        cultures: const <String>['en-US'],
      );
      expect(
        runner.lastArguments,
        containsAllInOrder(<String>['build', '-acceptEula', 'wix7']),
      );
      expect(
        runner.lastArguments,
        containsAllInOrder(<String>['-arch', 'x64']),
      );
    });

    test('should report the tool diagnostic, not just a code', () async {
      expect(
        () =>
            WixTool(
              runner: _StubRunner(exitCode: 1, stderr: 'error WIX0144: bad'),
            ).build(
              sourceFile: 'a.wxs',
              outputFile: 'a.msi',
              arch: TargetArch.x86_64,
              cultures: const <String>[],
            ),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure f) => f.remedy,
            'remedy',
            contains('WIX0144'),
          ),
        ),
      );
    });
  });
}

final class _StubRunner implements ProcessRunner {
  _StubRunner({this.exitCode = 0, this.stderr = ''});

  final int exitCode;
  final String stderr;
  List<String> lastArguments = const <String>[];

  @override
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdin,
    Duration? timeout,
  }) async {
    lastArguments = arguments;
    return ProcessOutcome(exitCode: exitCode, stdout: '', stderr: stderr);
  }
}

void _write(String path, String content) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}
