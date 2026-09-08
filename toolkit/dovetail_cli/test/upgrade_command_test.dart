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
    root = Directory.systemTemp.createTempSync('dovetail_upgrade');
    sdkHome = Directory.systemTemp.createTempSync('dovetail_upgrade_sdk');
    runner = CommandRunner<int>('dovetail', 'test')
      ..addCommand(UpgradeCommand(sdkLocator: SdkLocator(home: sdkHome.path)));
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

  Future<int?> upgrade(List<String> extra) =>
      runner.run(<String>['upgrade', '--root', root.path, ...extra]);

  String overridesText() =>
      File(p.join(root.path, 'pubspec_overrides.yaml')).readAsStringSync();

  bool overridesExist() =>
      File(p.join(root.path, 'pubspec_overrides.yaml')).existsSync();

  group('what it writes', () {
    test(
      'should write pubspec_overrides.yaml pointing at the installed SDK',
      () async {
        writeFile('pubspec.yaml', 'name: demo\nversion: 0.1.0\n');
        installSdk('0.2.0', <String>['dovetail', 'dovetail_rust_core']);

        expect(await upgrade(<String>[]), 0);

        final String overrides = overridesText();
        expect(overrides, contains('dependency_overrides:'));
        expect(overrides, contains('  dovetail:'));
        expect(
          overrides,
          contains(
            p.join(sdkHome.path, 'sdk', '0.2.0', 'packages', 'dovetail'),
          ),
        );
      },
    );

    test('should report the version transition by rewriting the file', () async {
      writeFile('pubspec.yaml', 'name: demo\nversion: 0.1.0\n');
      installSdk('0.2.0', <String>['dovetail']);
      writeFile(
        'pubspec_overrides.yaml',
        '# Written by dovetail. Do not version.\n'
            'dependency_overrides:\n'
            '  dovetail:\n'
            '    path: ${p.join(sdkHome.path, 'sdk', '0.0.9', 'packages', 'dovetail')}\n',
      );

      expect(await upgrade(<String>[]), 0);

      final String overrides = overridesText();
      expect(
        overrides,
        contains(p.join(sdkHome.path, 'sdk', '0.2.0', 'packages', 'dovetail')),
      );
      expect(
        overrides,
        isNot(contains('0.0.9')),
        reason:
            'o override antigo tinha de sumir por inteiro, não conviver '
            'com o novo',
      );
    });
  });

  void writeResolvablePubspec() {
    writeFile(
      'pubspec.yaml',
      'name: demo\nversion: 0.1.0\n\n'
          'environment:\n'
          '  sdk: ^3.0.0\n',
    );
  }

  void writeBrokenPubspec() {
    writeFile(
      'pubspec.yaml',
      'name: demo\nversion: 0.1.0\n\n'
          'environment:\n'
          '  sdk: ^3.0.0\n\n'
          'dependencies:\n'
          '  nonexistent_pkg: ^1.0.0\n',
    );
  }

  group('--check', () {
    test(
      'should exit 0 and keep the overrides when pub get resolves',
      () async {
        if (Process.runSync('which', <String>['dart']).exitCode != 0) {
          markTestSkipped('dart is not installed');
          return;
        }
        writeResolvablePubspec();
        installSdk('0.2.0', <String>['dovetail', 'dovetail_rust_core']);

        expect(await upgrade(<String>['--check']), 0);

        expect(overridesExist(), true);
        expect(overridesText(), contains('dependency_overrides:'));
      },
    );

    test(
      'should refuse, naming pub get, when the project does not resolve',
      () async {
        if (Process.runSync('which', <String>['dart']).exitCode != 0) {
          markTestSkipped('dart is not installed');
          return;
        }
        writeBrokenPubspec();
        installSdk('0.2.0', <String>['dovetail']);

        await expectLater(
          upgrade(<String>['--check']),
          throwsA(
            isA<UsageException>().having(
              (UsageException error) => error.message,
              'message',
              contains('pub get failed after re-pointing'),
            ),
          ),
        );
        // A recusa vem depois de re-apontar, então o override fica escrito.
        expect(overridesExist(), true);
      },
    );
  });

  group('what it refuses', () {
    test('a directory with no pubspec is not a project', () async {
      installSdk('0.2.0', <String>['dovetail']);

      await expectLater(
        upgrade(<String>[]),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('pubspec.yaml'),
          ),
        ),
      );
      expect(overridesExist(), false);
    });

    test(
      'without an installed SDK it refuses before writing anything',
      () async {
        writeFile('pubspec.yaml', 'name: demo\nversion: 0.1.0\n');

        await expectLater(
          upgrade(<String>[]),
          throwsA(
            isA<UsageException>().having(
              (UsageException error) => error.message,
              'message',
              contains('SDK'),
            ),
          ),
        );
        expect(overridesExist(), false);
      },
    );
  });
}
