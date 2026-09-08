import 'dart:io';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

/// The app this repository actually builds. Its plist is written by Xcode
/// from MACOSX_DEPLOYMENT_TARGET, which is the substitution this whole class
/// exists to trust.
String get _realApp => inRepo(<String>[
  'product',
  'vpn_desktop',
  'build',
  'macos',
  'Build',
  'Products',
  'Debug',
  'vpn_desktop.app',
]);

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('dovetail_minver'));
  tearDown(() => root.deleteSync(recursive: true));

  String bundleWith(String? body) {
    final Directory app = Directory(p.join(root.path, 'Example.app'))
      ..createSync();
    final Directory contents = Directory(p.join(app.path, 'Contents'))
      ..createSync();
    if (body != null) {
      File(p.join(contents.path, 'Info.plist')).writeAsStringSync(body);
    }
    return app.path;
  }

  String plist(String inner) =>
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<plist version="1.0"><dict>\n$inner\n</dict></plist>\n';

  group('reading', () {
    test('should find the version the key carries', () {
      expect(
        MinimumSystemVersion.readFrom(
          bundleWith(
            plist(
              '<key>CFBundleName</key><string>Example</string>\n'
              '<key>LSMinimumSystemVersion</key><string>11.0</string>',
            ),
          ),
        ),
        '11.0',
      );
    });

    test('should survive the whitespace a plist editor leaves behind', () {
      expect(
        MinimumSystemVersion.readFrom(
          bundleWith(
            plist(
              '<key>LSMinimumSystemVersion</key>\n  <string>10.14</string>',
            ),
          ),
        ),
        '10.14',
      );
    });

    test('a missing key should read as absent, not as empty', () {
      expect(
        MinimumSystemVersion.readFrom(
          bundleWith(plist('<key>CFBundleName</key><string>Example</string>')),
        ),
        isNull,
      );
    });

    test('a key with nothing in it should read as absent too', () {
      expect(
        MinimumSystemVersion.readFrom(
          bundleWith(
            plist('<key>LSMinimumSystemVersion</key><string></string>'),
          ),
        ),
        isNull,
      );
    });

    test('no Info.plist at all should refuse, not return null', () {
      expect(
        () => MinimumSystemVersion.readFrom(bundleWith(null)),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.message,
            'message',
            contains('no Info.plist'),
          ),
        ),
      );
    });

    test('a binary plist should be named as one, not parsed as garbage', () {
      final String app = bundleWith('bplist00 nonsense');
      expect(
        () => MinimumSystemVersion.readFrom(app),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.remedy,
            'remedy',
            contains('plutil -convert xml1'),
          ),
        ),
      );
    });
  });

  group('enforcing', () {
    test('a bundle with a floor and no claim should pass, and report it', () {
      expect(
        MinimumSystemVersion.enforce(
          bundlePath: bundleWith(
            plist('<key>LSMinimumSystemVersion</key><string>10.15</string>'),
          ),
        ),
        '10.15',
      );
    });

    test('a bundle with no floor should be refused before it ships', () {
      expect(
        () => MinimumSystemVersion.enforce(bundlePath: bundleWith(plist(''))),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.remedy,
            'remedy',
            contains('MACOSX_DEPLOYMENT_TARGET'),
          ),
        ),
      );
    });

    test('an unexpanded build setting should be caught', () {
      expect(
        () => MinimumSystemVersion.enforce(
          bundlePath: bundleWith(
            plist(
              '<key>LSMinimumSystemVersion</key>'
              r'<string>$(MACOSX_DEPLOYMENT_TARGET)</string>',
            ),
          ),
        ),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.remedy,
            'remedy',
            contains('no version at all'),
          ),
        ),
        reason:
            'the literal text is what the bundle would carry, and macOS reads '
            'it as nothing — the app then launches where it cannot run',
      );
    });

    test('a claim that disagrees with the bundle should refuse', () {
      expect(
        () => MinimumSystemVersion.enforce(
          bundlePath: bundleWith(
            plist('<key>LSMinimumSystemVersion</key><string>10.15</string>'),
          ),
          declared: '12.0',
        ),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.message,
            'message',
            allOf(contains('12.0'), contains('10.15')),
          ),
        ),
      );
    });

    test('a claim that agrees should pass', () {
      expect(
        MinimumSystemVersion.enforce(
          bundlePath: bundleWith(
            plist('<key>LSMinimumSystemVersion</key><string>10.15</string>'),
          ),
          declared: ' 10.15 ',
        ),
        '10.15',
      );
    });
  });

  group('against the app this repository actually builds', () {
    test('it should declare a floor that Xcode substituted', () {
      if (!Directory(_realApp).existsSync()) {
        // Repo-relative on purpose: the reason travels in the baseline, and
        // an absolute path would make the same skip read as a different
        // reason on a machine that clones elsewhere.
        markTestSkipped(
          'no built vpn_desktop.app in this checkout; run flutter build '
          'macos --debug in product/vpn_desktop first',
        );
        return;
      }
      final String found = MinimumSystemVersion.enforce(bundlePath: _realApp);
      expect(
        found,
        matches(RegExp(r'^\d+(\.\d+)*$')),
        reason:
            'this is the substitution the whole class trusts: the template '
            'says the build setting and the bundle has to carry a number',
      );
    });
  });
}
