import 'dart:io';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

final String _rust = inRepo(<String>[
  'toolkit',
  'dovetail_shortcut_channel',
  'rust',
]);

String _slice(TargetArch arch) => p.join(
  _rust,
  'target',
  arch.rustTriple(TargetOs.macos),
  'release',
  'libdesktop_shortcut_channel.dylib',
);

void main() {
  const UniversalBinary sut = UniversalBinary(runner: SystemProcessRunner());
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('dovetail_lipo'));
  tearDown(() => root.deleteSync(recursive: true));

  bool haveBothSlices() =>
      Platform.isMacOS &&
      File(_slice(TargetArch.x86_64)).existsSync() &&
      File(_slice(TargetArch.arm64)).existsSync();

  test('should read the architecture of a real single-slice library', () async {
    if (!haveBothSlices()) {
      markTestSkipped(
        'build the shortcut crate for both apple targets first: '
        'cargo build --release --target x86_64-apple-darwin and '
        '--target aarch64-apple-darwin',
      );
      return;
    }

    expect(await sut.architecturesOf(_slice(TargetArch.arm64)), <TargetArch>{
      TargetArch.arm64,
    });
    expect(await sut.architecturesOf(_slice(TargetArch.x86_64)), <TargetArch>{
      TargetArch.x86_64,
    });
  });

  test('should merge both slices into one binary that carries both', () async {
    if (!haveBothSlices()) {
      markTestSkipped('both apple slices are needed for this');
      return;
    }

    final String fat = await sut.merge(
      slices: <TargetArch, String>{
        TargetArch.x86_64: _slice(TargetArch.x86_64),
        TargetArch.arm64: _slice(TargetArch.arm64),
      },
      output: p.join(root.path, 'universal', 'libshortcut.dylib'),
    );

    expect(await sut.architecturesOf(fat), <TargetArch>{
      TargetArch.x86_64,
      TargetArch.arm64,
    });
    expect(
      File(fat).lengthSync(),
      greaterThan(File(_slice(TargetArch.arm64)).lengthSync()),
    );
  });

  test('should refuse a slice whose label does not match its bytes', () async {
    if (!haveBothSlices()) {
      markTestSkipped('both apple slices are needed for this');
      return;
    }

    await expectLater(
      sut.merge(
        slices: <TargetArch, String>{
          TargetArch.x86_64: _slice(TargetArch.arm64),
          TargetArch.arm64: _slice(TargetArch.x86_64),
        },
        output: p.join(root.path, 'wrong.dylib'),
      ),
      throwsA(
        isA<BundleFailure>().having(
          (BundleFailure failure) => failure.message,
          'message',
          contains('was given as the'),
        ),
      ),
      reason:
          'a merge that trusts the label is fat and still wrong on one arch',
    );
  });

  test('should refuse to call one slice universal', () async {
    await expectLater(
      sut.merge(
        slices: <TargetArch, String>{
          TargetArch.arm64: _slice(TargetArch.arm64),
        },
        output: p.join(root.path, 'thin.dylib'),
      ),
      throwsA(isA<BundleFailure>()),
    );
  });

  test('should refuse a slice that is not on disk', () async {
    await expectLater(
      sut.merge(
        slices: <TargetArch, String>{
          TargetArch.x86_64: p.join(root.path, 'absent-intel'),
          TargetArch.arm64: p.join(root.path, 'absent-arm'),
        },
        output: p.join(root.path, 'nothing.dylib'),
      ),
      throwsA(isA<BundleFailure>()),
    );
  });

  test('should refuse to read a path that does not exist', () async {
    await expectLater(
      sut.architecturesOf(p.join(root.path, 'nope')),
      throwsA(isA<BundleFailure>()),
    );
  });
}
