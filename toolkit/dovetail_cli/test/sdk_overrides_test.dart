import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_cli/src/sdk/sdk_locator.dart';
import 'package:dovetail_cli/src/sdk/sdk_overrides.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory home;
  late Directory sdkRoot;

  setUp(() {
    home = Directory.systemTemp.createTempSync('dovetail_sdk');
    sdkRoot = Directory(p.join(home.path, 'sdk'));
  });

  tearDown(() => home.deleteSync(recursive: true));

  void install(String version, List<String> packages) {
    final Directory packagesDir = Directory(
      p.join(sdkRoot.path, version, 'packages'),
    )..createSync(recursive: true);
    for (final String package in packages) {
      Directory(p.join(packagesDir.path, package)).createSync(recursive: true);
      File(
        p.join(packagesDir.path, package, 'pubspec.yaml'),
      ).writeAsStringSync('name: $package\nversion: $version\n');
    }
  }

  SdkInstall locate() => SdkLocator(home: home.path).locate()!;

  group('requireSdk', () {
    test('no SDK should refuse, naming install.sh as the remedy', () {
      expect(
        () => SdkOverrides.requireSdk(SdkLocator(home: home.path), 'usage'),
        throwsA(
          isA<UsageException>()
              .having(
                (UsageException error) => error.message,
                'message',
                contains('SDK'),
              )
              .having(
                (UsageException error) => error.usage,
                'usage',
                contains('install.sh'),
              ),
        ),
      );
    });
  });

  group('render', () {
    test('should point each package at its SDK copy, sorted', () {
      install('0.1.0', <String>['dovetail_rust_core', 'dovetail']);

      final String out = SdkOverrides.render(locate());

      expect(out, contains('dependency_overrides:'));
      expect(out, contains('  dovetail:'));
      expect(out, contains('  dovetail_rust_core:'));
      expect(
        out,
        contains(p.join(sdkRoot.path, '0.1.0', 'packages', 'dovetail')),
      );
      expect(
        out.indexOf('dovetail:'),
        lessThan(out.indexOf('dovetail_rust_core:')),
        reason: 'a ordem importa: o arquivo precisa ser estável entre corridas',
      );
    });

    test('a packages dir with no pubspec should refuse, naming the remedy', () {
      final Directory packagesDir = Directory(
        p.join(sdkRoot.path, '0.1.0', 'packages'),
      )..createSync(recursive: true);
      Directory(p.join(packagesDir.path, 'stray')).createSync(recursive: true);
      final SdkInstall sdk = SdkInstall(
        version: '0.1.0',
        packagesDir: packagesDir.path,
      );

      expect(
        () => SdkOverrides.render(sdk),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('no packages'),
          ),
        ),
      );
    });
  });
}
