import 'dart:io';

import 'package:dovetail_signer/src/signing_failure.dart';
import 'package:path/path.dart' as p;
import 'package:dovetail_process_runner/dovetail_process_runner.dart';

final class ChecksumWriter {
  const ChecksumWriter({required this.runner, this.shasum = 'shasum'});

  final ProcessRunner runner;
  final String shasum;

  static const String fileName = 'SHA256SUMS';

  Future<String> write({
    required List<String> files,
    required String outputDirectory,
  }) async {
    if (files.isEmpty) {
      throw const SigningFailure('no artefact was given to checksum.');
    }

    final String out = p.normalize(p.absolute(outputDirectory));
    final List<String> foreign = files
        .where((String file) => p.dirname(p.normalize(p.absolute(file))) != out)
        .toList(growable: false);
    if (foreign.isNotEmpty) {
      throw SigningFailure(
        '${foreign.length} artefact(s) live outside $outputDirectory: '
        '${foreign.map(p.basename).join(', ')}.',
        remedy:
            'Every line in $fileName names a file relative to the directory '
            'the file sits in. Mixing directories writes a $fileName that '
            'shasum -c cannot resolve, and nothing notices until a user '
            'checks the download.',
      );
    }

    final Set<String> seen = <String>{};
    for (final String file in files) {
      if (!File(file).existsSync()) {
        throw SigningFailure(
          'there is no artefact at $file to checksum.',
          remedy: 'A checksum of a file that does not exist verifies nothing.',
        );
      }
      if (!seen.add(p.basename(file))) {
        throw SigningFailure(
          '${p.basename(file)} is listed twice.',
          remedy: 'shasum -c would check the same file twice and miss another.',
        );
      }
    }

    final StringBuffer lines = StringBuffer();
    for (final String file in files) {
      final ProcessOutcome outcome = await runner.run(shasum, <String>[
        '-a',
        '256',
        p.basename(file),
      ], workingDirectory: out);
      if (!outcome.succeeded) {
        throw SigningFailure(
          'shasum failed on $file.',
          remedy: outcome.firstDiagnostic,
        );
      }
      lines.write(outcome.stdout);
    }

    final String destination = p.join(out, fileName);
    File(destination).writeAsStringSync(lines.toString());

    final ProcessOutcome verified = await runner.run(shasum, <String>[
      '-a',
      '256',
      '-c',
      fileName,
    ], workingDirectory: out);
    if (!verified.succeeded) {
      throw SigningFailure(
        'the $fileName this wrote does not verify against its own files.',
        remedy: verified.firstDiagnostic,
      );
    }

    return destination;
  }
}
