import 'dart:io';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const ProcessRunner _runner = SystemProcessRunner();

bool _present(String tool) =>
    Process.runSync('which', <String>[tool]).exitCode == 0;

String? _blocked() {
  if (!Platform.isMacOS) {
    return 'a Mach-O bundle only exists on macOS';
  }
  for (final String tool in <String>['rustc', 'lipo', 'ditto']) {
    if (!_present(tool)) {
      return '$tool is not installed';
    }
  }
  return null;
}

const Map<TargetArch, String> _triples = <TargetArch, String>{
  TargetArch.arm64: 'aarch64-apple-darwin',
  TargetArch.x86_64: 'x86_64-apple-darwin',
};

String _buildSingleArch(Directory root, TargetArch arch) {
  final Directory source = Directory(p.join(root.path, 'src_${arch.apple}'))
    ..createSync(recursive: true);
  File(p.join(source.path, 'main.rs')).writeAsStringSync('fn main() {}\n');

  final String bundle = p.join(root.path, arch.apple, 'Example.app');
  final Directory macos = Directory(p.join(bundle, 'Contents', 'MacOS'))
    ..createSync(recursive: true);
  Directory(p.join(bundle, 'Contents', 'Resources')).createSync();
  File(
    p.join(bundle, 'Contents', 'Resources', 'note.txt'),
  ).writeAsStringSync('not code');

  final ProcessResult built = Process.runSync('rustc', <String>[
    '--target',
    _triples[arch]!,
    '-o',
    p.join(macos.path, 'Example'),
    p.join(source.path, 'main.rs'),
  ]);
  if (built.exitCode != 0) {
    return '';
  }
  return bundle;
}

Set<String> _lipoArchs(String path) => Process.runSync('lipo', <String>[
  '-archs',
  path,
]).stdout.toString().trim().split(RegExp(r'\s+')).toSet();

void main() {
  final String? blocked = _blocked();
  late Directory root;

  setUp(() {
    if (blocked == null) {
      root = Directory.systemTemp.createTempSync('universal_bundle');
    }
  });

  tearDown(() {
    if (blocked == null) {
      root.deleteSync(recursive: true);
    }
  });

  group('what it refuses before copying anything', () {
    test('one build is not a universal bundle', () async {
      await expectLater(
        const UniversalBundle(runner: _runner).assemble(
          bundles: <TargetArch, String>{TargetArch.arm64: '/tmp/A.app'},
          output: '/tmp/U.app',
        ),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.remedy,
            'remedy',
            contains('will not start on half'),
          ),
        ),
      );
    });

    test('a build that is not there should be named', () async {
      await expectLater(
        const UniversalBundle(runner: _runner).assemble(
          bundles: <TargetArch, String>{
            TargetArch.arm64: '/tmp/no-such-arm.app',
            TargetArch.x86_64: '/tmp/no-such-intel.app',
          },
          output: '/tmp/U.app',
        ),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.message,
            'message',
            contains('no-such-arm.app'),
          ),
        ),
      );
    });
  });

  group('against two real single-architecture bundles', () {
    test(
      'the result should carry both slices in every Mach-O',
      () async {
        if (blocked != null) {
          markTestSkipped(blocked);
          return;
        }

        final String arm = _buildSingleArch(root, TargetArch.arm64);
        final String intel = _buildSingleArch(root, TargetArch.x86_64);
        if (arm.isEmpty || intel.isEmpty) {
          markTestSkipped('rustup target add both apple-darwin targets');
          return;
        }

        final String universal = await const UniversalBundle(runner: _runner)
            .assemble(
              bundles: <TargetArch, String>{
                TargetArch.arm64: arm,
                TargetArch.x86_64: intel,
              },
              output: p.join(root.path, 'Example.app'),
            );

        expect(
          _lipoArchs(p.join(universal, 'Contents', 'MacOS', 'Example')),
          <String>{'arm64', 'x86_64'},
          reason: 'the dmg refuses to ship one architecture under both names',
        );
        expect(
          File(
            p.join(universal, 'Contents', 'Resources', 'note.txt'),
          ).existsSync(),
          true,
          reason: 'everything that is not code is carried across unchanged',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'a binary present in one build only should be refused',
      () async {
        if (blocked != null) {
          markTestSkipped(blocked);
          return;
        }

        final String arm = _buildSingleArch(root, TargetArch.arm64);
        final String intel = _buildSingleArch(root, TargetArch.x86_64);
        if (arm.isEmpty || intel.isEmpty) {
          markTestSkipped('rustup target add both apple-darwin targets');
          return;
        }

        File(
          p.join(arm, 'Contents', 'MacOS', 'Example'),
        ).copySync(p.join(arm, 'Contents', 'MacOS', 'OnlyOnArm'));

        await expectLater(
          const UniversalBundle(runner: _runner).assemble(
            bundles: <TargetArch, String>{
              TargetArch.arm64: arm,
              TargetArch.x86_64: intel,
            },
            output: p.join(root.path, 'Example.app'),
          ),
          throwsA(
            isA<BundleFailure>()
                .having(
                  (BundleFailure failure) => failure.message,
                  'message',
                  contains('OnlyOnArm'),
                )
                .having(
                  (BundleFailure failure) => failure.remedy,
                  'remedy',
                  contains('missing on exactly one architecture'),
                ),
          ),
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'a bundle with no Mach-O at all should be refused',
      () async {
        if (blocked != null) {
          markTestSkipped(blocked);
          return;
        }

        final String empty = p.join(root.path, 'Empty.app');
        Directory(
          p.join(empty, 'Contents', 'MacOS'),
        ).createSync(recursive: true);
        final String other = p.join(root.path, 'Other.app');
        Directory(
          p.join(other, 'Contents', 'MacOS'),
        ).createSync(recursive: true);

        await expectLater(
          const UniversalBundle(runner: _runner).assemble(
            bundles: <TargetArch, String>{
              TargetArch.arm64: empty,
              TargetArch.x86_64: other,
            },
            output: p.join(root.path, 'Example.app'),
          ),
          throwsA(
            isA<BundleFailure>().having(
              (BundleFailure failure) => failure.remedy,
              'remedy',
              contains('was not built'),
            ),
          ),
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
