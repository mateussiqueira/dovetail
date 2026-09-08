import 'dart:io';

import 'package:dovetail_signer/dovetail_signer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

final String _builtApp = inRepo(<String>[
  'product',
  'vpn_desktop',
  'build',
  'macos',
  'Build',
  'Products',
  'Debug',
  'vpn_desktop.app',
]);

List<String> walk(String root) {
  final List<String> found = <String>[];
  for (final FileSystemEntity entity in Directory(
    root,
  ).listSync(recursive: true, followLinks: false)) {
    found.add(entity.path);
  }
  return found;
}

void main() {
  group('against the app this repository actually builds', () {
    late String bundle;

    setUpAll(() {
      if (!Platform.isMacOS || !Directory(_builtApp).existsSync()) {
        bundle = '';
        return;
      }
      final Directory scratch = Directory.systemTemp.createTempSync('signer');
      final ProcessResult copied = Process.runSync('cp', <String>[
        '-R',
        _builtApp,
        scratch.path,
      ]);
      if (copied.exitCode != 0) {
        throw StateError(
          'the app is there and could not be copied, which is a failure and '
          'not a reason to skip: ${copied.stderr}',
        );
      }
      bundle = p.join(scratch.path, p.basename(_builtApp));
    });

    test(
      'signing inside out ad hoc should satisfy the system verifier',
      () async {
        if (bundle.isEmpty) {
          markTestSkipped(
            'needs macOS and a built vpn_desktop.app; run '
            'flutter build macos --debug in product/vpn_desktop first',
          );
          return;
        }

        const MacosSigner sut = MacosSigner(runner: SystemProcessRunner());
        final List<SignTarget> order = await sut.sign(
          request: MacosSigningRequest(bundlePath: bundle, identity: '-'),
          contents: walk(bundle),
        );

        expect(order.last.path, bundle);
        expect(order.length, greaterThan(1));

        final ProcessResult verified = Process.runSync('codesign', <String>[
          '--verify',
          '--deep',
          '--strict',
          '--verbose=2',
          bundle,
        ]);

        expect(
          verified.exitCode,
          0,
          reason:
              'codesign --verify --deep --strict rejected the bundle:\n'
              '${verified.stderr}',
        );
      },
    );

    test('the signed bundle should report a signature, not an absence', () {
      if (bundle.isEmpty) {
        markTestSkipped('needs macOS and a built vpn_desktop.app');
        return;
      }

      final ProcessResult display = Process.runSync('codesign', <String>[
        '-dvv',
        bundle,
      ]);

      expect(display.stderr.toString(), contains('Signature'));
    });
  });
}
