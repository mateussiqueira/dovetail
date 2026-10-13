import 'dart:io';
import 'dart:typed_data';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

List<int> thinHeaderFor(int cpuType) {
  final ByteData data = ByteData(8)
    ..setUint32(0, 0xFEEDFACF, Endian.little)
    ..setUint32(4, cpuType, Endian.little);
  return data.buffer.asUint8List();
}

List<int> fatHeaderFor(List<int> cpuTypes) {
  final ByteData data = ByteData(8 + 20 * cpuTypes.length)
    ..setUint32(0, 0xCAFEBABE)
    ..setUint32(4, cpuTypes.length);
  for (int index = 0; index < cpuTypes.length; index++) {
    data.setUint32(8 + 20 * index, cpuTypes[index]);
  }
  return data.buffer.asUint8List();
}

final List<int> _fatBoth = fatHeaderFor(<int>[
  MachO.cpuTypeX86_64,
  MachO.cpuTypeArm64,
]);

final class _Recording implements ProcessRunner {
  _Recording({this.exitCode = 0});

  final int exitCode;
  final List<List<String>> calls = <List<String>>[];

  @override
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdin,
    Duration? timeout,
  }) async {
    calls.add(<String>[executable, ...arguments]);
    return ProcessOutcome(exitCode: exitCode, stdout: '', stderr: 'lipo: no');
  }
}

late Directory root;

String bundleWith(Map<String, List<int>> files) {
  final String bundle = p.join(root.path, 'Example.app');
  for (final MapEntry<String, List<int>> file in files.entries) {
    File(p.join(bundle, file.key))
      ..createSync(recursive: true)
      ..writeAsBytesSync(<int>[...file.value, ...List<int>.filled(64, 0)]);
  }
  return bundle;
}

void main() {
  setUp(() => root = Directory.systemTemp.createTempSync('dovetail_thin'));
  tearDown(() => root.deleteSync(recursive: true));

  test('only a fat binary should reach lipo, thinned in place', () async {
    final String bundle = bundleWith(<String, List<int>>{
      'Contents/MacOS/Example': _fatBoth,
      'Contents/Frameworks/Thin.dylib': thinHeaderFor(MachO.cpuTypeArm64),
    });
    final _Recording runner = _Recording();

    final List<String> thinned = await BundleThinner(
      runner: runner,
    ).thin(bundlePath: bundle, architecture: TargetArch.arm64);

    final String fat = p.join(bundle, 'Contents', 'MacOS', 'Example');
    expect(runner.calls, <List<String>>[
      <String>['lipo', fat, '-thin', 'arm64', '-output', fat],
    ]);
    expect(thinned, <String>['Contents/MacOS/Example']);
  });

  test('a binary without the slice should be refused before lipo', () async {
    final String bundle = bundleWith(<String, List<int>>{
      'Contents/MacOS/Example': _fatBoth,
      'Contents/Frameworks/Intel.dylib': thinHeaderFor(MachO.cpuTypeX86_64),
    });
    final _Recording runner = _Recording();

    await expectLater(
      BundleThinner(
        runner: runner,
      ).thin(bundlePath: bundle, architecture: TargetArch.arm64),
      throwsA(
        isA<BundleFailure>().having(
          (BundleFailure failure) => failure.message,
          'message',
          contains('Contents/Frameworks/Intel.dylib'),
        ),
      ),
    );
    expect(runner.calls, isEmpty);
  });

  test('a lipo that fails should be named with the file', () async {
    final String bundle = bundleWith(<String, List<int>>{
      'Contents/MacOS/Example': _fatBoth,
    });

    await expectLater(
      BundleThinner(
        runner: _Recording(exitCode: 1),
      ).thin(bundlePath: bundle, architecture: TargetArch.arm64),
      throwsA(
        isA<BundleFailure>().having(
          (BundleFailure failure) => failure.message,
          'message',
          contains('Contents/MacOS/Example'),
        ),
      ),
    );
  });
}
