import 'dart:io';

import 'package:dovetail_signer/dovetail_signer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('checksums');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('write should refuse an empty artefact list', () async {
    const ChecksumWriter sut = ChecksumWriter(runner: SystemProcessRunner());

    await expectLater(
      sut.write(files: const <String>[], outputDirectory: root.path),
      throwsA(isA<SigningFailure>()),
    );
  });

  test(
    'write should produce a SHA256SUMS the system tool can verify',
    () async {
      final File artefact = File(p.join(root.path, 'example.deb'))
        ..writeAsStringSync('payload');
      const ChecksumWriter sut = ChecksumWriter(runner: SystemProcessRunner());

      final String sums = await sut.write(
        files: <String>[artefact.path],
        outputDirectory: root.path,
      );

      expect(File(sums).existsSync(), true);
      expect(File(sums).readAsStringSync(), contains('example.deb'));

      final ProcessResult checked = Process.runSync('shasum', <String>[
        '-a',
        '256',
        '-c',
        p.basename(sums),
      ], workingDirectory: root.path);
      expect(checked.exitCode, 0, reason: checked.stdout.toString());
    },
  );

  test('a tampered artefact should fail the verification', () async {
    final File artefact = File(p.join(root.path, 'example.deb'))
      ..writeAsStringSync('payload');
    const ChecksumWriter sut = ChecksumWriter(runner: SystemProcessRunner());
    final String sums = await sut.write(
      files: <String>[artefact.path],
      outputDirectory: root.path,
    );

    artefact.writeAsStringSync('tampered');

    final ProcessResult checked = Process.runSync('shasum', <String>[
      '-a',
      '256',
      '-c',
      p.basename(sums),
    ], workingDirectory: root.path);
    expect(checked.exitCode, isNot(0));
  });
}
