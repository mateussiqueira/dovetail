import 'dart:io';

import 'package:dovetail_cli/src/dovetail_version.dart';
import 'package:dovetail_cli/src/sdk/sdk_locator.dart';
import 'package:dovetail_cli/src/sdk/version_order.dart';
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

  SdkInstall? locate() => SdkLocator(home: home.path).locate();

  group('when nothing is installed', () {
    test('an empty home resolves to nothing', () {
      expect(locate(), isNull);
    });

    test('a directory without packages/ is not a version', () {
      Directory(p.join(sdkRoot.path, '0.1.0')).createSync(recursive: true);

      expect(locate(), isNull);
    });

    test('a version whose packages/ is empty still locates', () {
      Directory(
        p.join(sdkRoot.path, '0.1.0', 'packages'),
      ).createSync(recursive: true);

      final SdkInstall? sdk = locate();
      expect(sdk, isNotNull);
      expect(sdk!.packages(), isEmpty);
    });
  });

  group('which version it picks', () {
    test('the version of the running binary wins when installed', () {
      install('0.0.9', <String>['dovetail']);
      install(DovetailVersion.number, <String>['dovetail']);
      install('0.2.0', <String>['dovetail']);

      expect(locate()!.version, DovetailVersion.number);
    });

    test('the newest wins by numeric order, not lexicographic', () {
      install('0.9.0', <String>['dovetail']);
      install('0.10.0', <String>['dovetail']);

      expect(
        locate()!.version,
        '0.10.0',
        reason:
            'sort de string põe 0.10.0 antes de 0.9.0, e a "mais recente" '
            'sairia errada',
      );
    });
  });

  group('what packages() lists', () {
    test('only directories that carry a pubspec', () {
      install('0.1.0', <String>['dovetail', 'dovetail_rust_core']);
      Directory(
        p.join(sdkRoot.path, '0.1.0', 'packages', 'stray'),
      ).createSync(recursive: true);

      expect(
        locate()!.packages(),
        <String>['dovetail', 'dovetail_rust_core'],
        reason: 'um diretório solto viraria um override que o pub recusa',
      );
    });

    test('sorted, so the overrides file is stable', () {
      install('0.1.0', <String>[
        'dovetail_rust_core',
        'dovetail',
        'dovetail_form_validation',
      ]);

      expect(locate()!.packages(), <String>[
        'dovetail',
        'dovetail_form_validation',
        'dovetail_rust_core',
      ]);
    });

    test('the packagesDir points at the picked version', () {
      install('0.1.0', <String>['dovetail']);

      expect(locate()!.packagesDir, p.join(sdkRoot.path, '0.1.0', 'packages'));
    });
  });

  group('newerVersion — one rule, both ends', () {
    test('equal versions are equal, in any order', () {
      expect(newerVersion('0.1.0', '0.1.0'), '0.1.0');
    });

    test('a longer version wins over a shorter prefix', () {
      expect(
        newerVersion('0.1.0', '0.1'),
        '0.1.0',
        reason: '0.1.0 é 0.1 com um patch lançado — mais nova, não igual',
      );
    });

    test('the decision is symmetric', () {
      expect(newerVersion('0.2.0', '0.1.0'), '0.2.0');
      expect(newerVersion('0.1.0', '0.2.0'), '0.2.0');
    });
  });
}
