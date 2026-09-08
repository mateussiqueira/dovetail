import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:dovetail_cli/src/sdk/sdk_locator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory sdkHome;
  late CommandRunner<int> runner;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_init');
    sdkHome = Directory.systemTemp.createTempSync('dovetail_sdk_home');
    runner = CommandRunner<int>('dovetail', 'test')
      ..addCommand(InitCommand(sdkLocator: SdkLocator(home: sdkHome.path)));
  });

  tearDown(() {
    root.deleteSync(recursive: true);
    sdkHome.deleteSync(recursive: true);
  });

  void writeFile(String relative, String content) {
    final File file = File(p.join(root.path, relative))
      ..parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  void installSdk(String version, List<String> packages) {
    final Directory packagesDir = Directory(
      p.join(sdkHome.path, 'sdk', version, 'packages'),
    )..createSync(recursive: true);
    for (final String package in packages) {
      Directory(p.join(packagesDir.path, package)).createSync(recursive: true);
      File(
        p.join(packagesDir.path, package, 'pubspec.yaml'),
      ).writeAsStringSync('name: $package\nversion: $version\n');
    }
  }

  void flutterProject({
    String version = '1.4.2+9',
    List<String> platforms = const <String>['macos', 'linux'],
    String name = 'vpn_desktop',
  }) {
    writeFile('pubspec.yaml', 'name: $name\nversion: $version\n');
    for (final String platform in platforms) {
      Directory(p.join(root.path, platform)).createSync(recursive: true);
    }
  }

  Future<int?> init(List<String> extra) =>
      runner.run(<String>['init', '--root', root.path, ...extra]);

  DovetailConfig written() => DovetailConfig.parse(
    File(p.join(root.path, ConfigLocator.fileName)).readAsStringSync(),
  );

  group('what it reads off the project', () {
    test('desktop directories should become platform keys', () async {
      flutterProject(platforms: <String>['macos', 'windows']);

      expect(await init(<String>[]), 0);
      expect(written().targets, <String>[
        'darwin-x86_64',
        'darwin-aarch64',
        'windows-x86_64',
        'windows-aarch64',
      ]);
    });

    test('a platform with no directory should not be offered', () async {
      flutterProject(platforms: <String>['linux']);

      await init(<String>[]);
      expect(
        written().targets.every((String key) => key.startsWith('linux-')),
        true,
      );
    });

    test('the package name should become a readable product name', () async {
      flutterProject(name: 'my_vpn_client');

      await init(<String>[]);
      expect(written().name, 'My Vpn Client');
    });

    test('the identifier should come from the macos config, not the '
        'test target', () async {
      flutterProject();
      writeFile(
        p.join('macos', 'Runner', 'Configs', 'AppInfo.xcconfig'),
        'PRODUCT_BUNDLE_IDENTIFIER = io.example.app\n',
      );
      writeFile(
        p.join('macos', 'Runner.xcodeproj', 'project.pbxproj'),
        'PRODUCT_BUNDLE_IDENTIFIER = io.example.app.RunnerTests;\n',
      );

      await init(<String>[]);
      expect(
        written().identifier,
        'io.example.app',
        reason:
            'the only bundle id in a default pbxproj belongs to RunnerTests, '
            'and shipping under it would key the single-instance guard and '
            'the deep-link scheme off the test bundle',
      );
    });

    test('--identifier should win over anything detected', () async {
      flutterProject();
      writeFile(
        p.join('linux', 'CMakeLists.txt'),
        'set(APPLICATION_ID "io.example.detected")\n',
      );

      await init(<String>['--identifier', 'io.example.chosen']);
      expect(written().identifier, 'io.example.chosen');
    });

    test('a project with no identifier should still write a parseable '
        'file', () async {
      flutterProject(name: 'thing');

      expect(await init(<String>[]), 0);
      expect(written().identifier, 'com.example.thing');
    });

    test('an underscore in the package name should not reach the '
        'identifier', () async {
      flutterProject(name: 'vpn_desktop');

      expect(await init(<String>[]), 0);
      expect(
        written().identifier,
        'com.example.vpn-desktop',
        reason:
            'CFBundleIdentifier takes alphanumerics, hyphens and dots only, so '
            'an underscore makes a bundle macOS refuses to launch',
      );
    });
  });

  group('what it refuses', () {
    test('a directory with no pubspec is not a project', () async {
      await expectLater(
        init(<String>[]),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('pubspec.yaml'),
          ),
        ),
      );
    });

    test('an existing config should not be overwritten by accident', () async {
      flutterProject();
      await init(<String>[]);

      await expectLater(
        init(<String>[]),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('already'),
          ),
        ),
      );
    });

    test('--force should overwrite it', () async {
      flutterProject();
      await init(<String>[]);
      File(
        p.join(root.path, ConfigLocator.fileName),
      ).writeAsStringSync('# edited by hand\n');

      expect(await init(<String>['--force']), 0);
      expect(written().identifier, isNotEmpty);
    });
  });

  group('the file it writes', () {
    test('should always parse as the config the commands read', () async {
      for (final List<String> platforms in <List<String>>[
        <String>['macos'],
        <String>['macos', 'windows', 'linux'],
        <String>[],
      ]) {
        root.deleteSync(recursive: true);
        root.createSync(recursive: true);
        flutterProject(platforms: platforms);

        if (platforms.isEmpty) {
          await expectLater(
            init(<String>[]),
            throwsA(
              isA<UsageException>().having(
                (UsageException error) => error.message,
                'message',
                contains('no macos, windows or linux directory'),
              ),
            ),
            reason:
                'writing a config whose own parser rejects it is worse than '
                'saying there is no desktop build here to configure',
          );
          expect(
            File(p.join(root.path, ConfigLocator.fileName)).existsSync(),
            false,
          );
          continue;
        }

        expect(await init(<String>[]), 0);
        expect(written().targets, isNotEmpty, reason: platforms.join(','));
      }
    });

    test(
      'should never carry a signing identity, only variable names',
      () async {
        flutterProject();
        await init(<String>[]);

        final String source = File(
          p.join(root.path, ConfigLocator.fileName),
        ).readAsStringSync();

        expect(source, contains('identity-env'));
        expect(source, contains('certificate-env'));
        expect(
          RegExp('Developer ID|BEGIN .*PRIVATE KEY').hasMatch(source),
          false,
          reason: 'this file is meant to be committed',
        );
      },
    );

    test('should not repeat the version that pubspec already holds', () async {
      flutterProject(version: '1.4.2+9');
      await init(<String>[]);

      expect(
        File(p.join(root.path, ConfigLocator.fileName)).readAsStringSync(),
        isNot(contains('1.4.2')),
      );
      expect(PubspecVersion.read(root.path), '1.4.2');
    });
  });

  group('--sdk', () {
    test('an installed SDK becomes the runtime source', () async {
      flutterProject();
      installSdk('0.1.0', <String>[
        'dovetail',
        'dovetail_updater',
        'dovetail_rust_core',
      ]);

      expect(await init(<String>['--sdk']), 0);

      final File overrides = File(p.join(root.path, 'pubspec_overrides.yaml'));
      expect(overrides.existsSync(), true);
      final String text = overrides.readAsStringSync();
      expect(text, contains('dependency_overrides:'));
      expect(
        text,
        contains(
          '  dovetail:\n'
          '    path: "${p.join(sdkHome.path, 'sdk', '0.1.0', 'packages', 'dovetail')}"',
        ),
      );
      expect(text, contains('  dovetail_rust_core:'));
    });

    test('without --sdk no overrides file is written', () async {
      flutterProject();
      installSdk('0.1.0', <String>['dovetail']);

      expect(await init(<String>[]), 0);
      expect(
        File(p.join(root.path, 'pubspec_overrides.yaml')).existsSync(),
        false,
        reason: 'sem a flag o runtime continua resolvendo pelo pubspec',
      );
    });

    test(
      '--sdk without an installed SDK refuses before writing anything',
      () async {
        flutterProject();

        await expectLater(
          init(<String>['--sdk']),
          throwsA(
            isA<UsageException>().having(
              (UsageException error) => error.message,
              'message',
              contains('SDK'),
            ),
          ),
        );
        expect(
          File(p.join(root.path, ConfigLocator.fileName)).existsSync(),
          false,
          reason:
              'sair com a config escrita e o override de fora é o estado pela '
              'metade que um --force teria que desfazer',
        );
        expect(
          File(p.join(root.path, 'pubspec_overrides.yaml')).existsSync(),
          false,
        );
      },
    );

    test('a project without pubspec refuses as before, SDK or not', () async {
      await expectLater(
        init(<String>['--sdk']),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('pubspec.yaml'),
          ),
        ),
        reason:
            'o SDK é procurado depois das checagens de projeto: a falta de '
            'pubspec é o erro que o usuário precisa ver primeiro',
      );
    });
  });
}
