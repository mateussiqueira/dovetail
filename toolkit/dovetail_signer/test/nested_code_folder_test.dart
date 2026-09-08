import 'dart:io';

import 'package:dovetail_signer/dovetail_signer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String _plist(String executable, String identifier, String type) =>
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
    '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    '<plist version="1.0">\n<dict>\n'
    '  <key>CFBundleExecutable</key><string>$executable</string>\n'
    '  <key>CFBundleIdentifier</key><string>$identifier</string>\n'
    '  <key>CFBundlePackageType</key><string>$type</string>\n'
    '  <key>CFBundleShortVersionString</key><string>1.0.0</string>\n'
    '</dict>\n</plist>\n';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('dovetail_nested'));
  tearDown(() => root.deleteSync(recursive: true));

  String bundleWith(List<String> relativePaths) {
    final String app = p.join(root.path, 'Probe.app');
    for (final String relative in relativePaths) {
      File(p.join(app, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('x');
    }
    return app;
  }

  List<SignTarget> orderFor(String app) => SignOrder.insideOut(
    bundlePath: app,
    contents: Directory(app)
        .listSync(recursive: true, followLinks: false)
        .map((FileSystemEntity entity) => entity.path)
        .toList(),
  );

  group('SignOrder and the folders Apple actually names', () {
    test('PlugIns should be covered, capital I and all', () {
      final String app = bundleWith(<String>[
        'Contents/MacOS/Probe',
        'Contents/PlugIns/Thing.bundle/Contents/MacOS/Thing',
      ]);

      expect(
        orderFor(app).map((SignTarget target) => target.path),
        contains(p.join(app, 'Contents', 'PlugIns', 'Thing.bundle')),
        reason:
            'the folder on disk is PlugIns; a set holding Plugins misses it, '
            'sign() completes, and the app fails codesign --deep --strict',
      );
    });

    test('every nested code folder Apple defines should be covered', () {
      final String app = bundleWith(<String>[
        'Contents/MacOS/Probe',
        'Contents/Frameworks/Helper.framework/Versions/A/Helper',
        'Contents/PlugIns/Thing.bundle/Contents/MacOS/Thing',
        'Contents/XPCServices/Svc.xpc/Contents/MacOS/Svc',
        'Contents/Extensions/Ext.appex/Contents/MacOS/Ext',
        'Contents/Helpers/Helper.app/Contents/MacOS/Helper',
        'Contents/Libraries/lib.dylib',
        'Contents/Resources/icon.png',
      ]);

      final Iterable<String> signed = orderFor(
        app,
      ).map((SignTarget target) => target.path);

      for (final String folder in <String>[
        'Frameworks',
        'PlugIns',
        'XPCServices',
        'Extensions',
        'Helpers',
        'Libraries',
      ]) {
        expect(
          signed.any((String path) => path.contains('/$folder/')),
          true,
          reason: folder,
        );
      }
    });

    test('Resources should not be signed as code', () {
      final String app = bundleWith(<String>[
        'Contents/MacOS/Probe',
        'Contents/Resources/icon.png',
      ]);
      expect(
        orderFor(app).map((SignTarget target) => target.path),
        isNot(contains(p.join(app, 'Contents', 'Resources', 'icon.png'))),
      );
    });

    test('the folder name should match whatever case the disk used', () {
      expect(SignOrder.isNestedCodeFolder('PlugIns'), true);
      expect(SignOrder.isNestedCodeFolder('Plugins'), true);
      expect(SignOrder.isNestedCodeFolder('plugins'), true);
      expect(SignOrder.isNestedCodeFolder('MacOS'), true);
      expect(SignOrder.isNestedCodeFolder('Resources'), false);
      expect(SignOrder.isNestedCodeFolder('SharedSupport'), false);
    });

    test('a library should be sealed, not given the hardened runtime', () {
      final String app = bundleWith(<String>[
        'Contents/MacOS/Probe',
        'Contents/Libraries/lib.dylib',
      ]);
      final SignTarget library = orderFor(
        app,
      ).firstWhere((SignTarget target) => target.path.endsWith('.dylib'));
      expect(library.isExecutable, false);
    });

    test('the bundle itself should still be last', () {
      final String app = bundleWith(<String>[
        'Contents/MacOS/Probe',
        'Contents/PlugIns/Thing.bundle/Contents/MacOS/Thing',
        'Contents/Frameworks/Helper.framework/Versions/A/Helper',
      ]);
      expect(orderFor(app).last.path, app);
    });

    test('only the direct children of a code folder should be signed', () {
      final String app = bundleWith(<String>[
        'Contents/MacOS/Probe',
        'Contents/Frameworks/App.framework/Versions/A/Resources/assets/icon.png',
      ]);
      expect(
        orderFor(app).map((SignTarget target) => target.path),
        isNot(
          contains(
            p.join(
              app,
              'Contents',
              'Frameworks',
              'App.framework',
              'Versions',
              'A',
              'Resources',
              'assets',
            ),
          ),
        ),
        reason:
            'codesign refuses a directory that is not a bundle with "bundle '
            'format unrecognized"',
      );
    });
  });

  group('against the real codesign', () {
    bool canSign() =>
        Platform.isMacOS &&
        Process.runSync('which', <String>['codesign']).exitCode == 0 &&
        Process.runSync('which', <String>['rustc']).exitCode == 0;

    test(
      'a bundle with a PlugIns bundle should verify --deep --strict',
      () async {
        if (!canSign()) {
          markTestSkipped('needs macOS with codesign and rustc');
          return;
        }

        final String source = p.join(root.path, 'm.rs');
        File(source).writeAsStringSync('fn main() { println!("p"); }\n');
        final String binary = p.join(root.path, 'bin');
        final ProcessResult built = Process.runSync('rustc', <String>[
          '-O',
          '-o',
          binary,
          source,
        ]);
        expect(built.exitCode, 0, reason: built.stderr.toString());

        final String app = p.join(root.path, 'Real.app');
        final String plugin = p.join(
          app,
          'Contents',
          'PlugIns',
          'Thing.bundle',
        );
        Directory(p.join(app, 'Contents', 'MacOS')).createSync(recursive: true);
        Directory(
          p.join(plugin, 'Contents', 'MacOS'),
        ).createSync(recursive: true);
        File(binary).copySync(p.join(app, 'Contents', 'MacOS', 'Real'));
        File(binary).copySync(p.join(plugin, 'Contents', 'MacOS', 'Thing'));
        File(
          p.join(app, 'Contents', 'Info.plist'),
        ).writeAsStringSync(_plist('Real', 'io.example.real', 'APPL'));
        File(
          p.join(plugin, 'Contents', 'Info.plist'),
        ).writeAsStringSync(_plist('Thing', 'io.example.real.thing', 'BNDL'));

        final List<SignTarget> order =
            await const MacosSigner(runner: SystemProcessRunner()).sign(
              request: MacosSigningRequest(bundlePath: app, identity: '-'),
              contents: Directory(app)
                  .listSync(recursive: true, followLinks: false)
                  .map((FileSystemEntity entity) => entity.path)
                  .toList(),
            );

        expect(order, hasLength(3));

        final ProcessResult verified = Process.runSync('codesign', <String>[
          '--verify',
          '--deep',
          '--strict',
          app,
        ]);
        expect(
          verified.exitCode,
          0,
          reason:
              'measured: with the plugin skipped, sign() still completes and '
              'this exits 1 — the release passes the build and Apple rejects '
              'it. ${verified.stderr}',
        );
      },
    );
  });
}
