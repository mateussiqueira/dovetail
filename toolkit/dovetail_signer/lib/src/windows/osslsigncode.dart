import 'dart:io';

import 'package:dovetail_signer/src/signing_failure.dart';
import 'package:dovetail_signer/src/windows/osslsigncode_request.dart';
import 'package:path/path.dart' as p;
import 'package:dovetail_process_runner/dovetail_process_runner.dart';

final class Osslsigncode {
  const Osslsigncode({required this.runner, this.executable = 'osslsigncode'});

  final ProcessRunner runner;
  final String executable;

  static const Set<String> signableExtensions = <String>{
    '.exe',
    '.dll',
    '.sys',
    '.msi',
    '.cab',
    '.ps1',
  };

  List<String> argumentsFor(
    OsslsigncodeRequest request, {
    required String input,
    required String output,
  }) {
    if (request.timestampUrl.trim().isEmpty) {
      throw const SigningFailure(
        'no timestamp server was given.',
        remedy:
            'A signature without a timestamp stops verifying the day the '
            'certificate expires, on machines that already installed the app. '
            'There is no default here on purpose.',
      );
    }
    if (request.digestAlgorithm.trim().isEmpty) {
      throw const SigningFailure(
        'no digest algorithm was given.',
        remedy: 'The next flag would be read as the algorithm name.',
      );
    }
    if (p.canonicalize(input) == p.canonicalize(output)) {
      throw const SigningFailure(
        'the input and the output are the same file.',
        remedy:
            'osslsigncode refuses to sign in place, and writing over the input '
            'mid-read truncates the artefact that was going to be shipped.',
      );
    }

    return <String>[
      'sign',
      ...request.credentialArguments(),
      '-h',
      request.digestAlgorithm,
      '-ts',
      request.timestampUrl,
      if (request.programName != null) ...<String>['-n', request.programName!],
      if (request.programUrl != null) ...<String>['-i', request.programUrl!],
      '-in',
      input,
      '-out',
      output,
    ];
  }

  Future<void> sign(OsslsigncodeRequest request, String artifactPath) async {
    final String extension = p.extension(artifactPath).toLowerCase();
    if (!signableExtensions.contains(extension)) {
      throw SigningFailure(
        '"$extension" is not a format Authenticode covers.',
        remedy:
            'It signs ${signableExtensions.join(', ')}. A zip or a bare '
            'directory carries no signature, and signing one silently does '
            'nothing a client can check.',
      );
    }
    if (!File(artifactPath).existsSync()) {
      throw SigningFailure('there is nothing at $artifactPath to sign.');
    }

    final String staged = '$artifactPath.signing';
    final ProcessOutcome signed = await runner.run(
      executable,
      argumentsFor(request, input: artifactPath, output: staged),
    );

    if (!signed.succeeded || !File(staged).existsSync()) {
      if (File(staged).existsSync()) {
        File(staged).deleteSync();
      }
      throw SigningFailure(
        'osslsigncode exited with ${signed.exitCode} and signed nothing.',
        remedy: signed.stderr.trim().isEmpty
            ? 'The artefact was left as it was. ${signed.stdout.trim()}'
            : signed.stderr.trim(),
      );
    }

    File(staged).renameSync(artifactPath);
  }

  Future<bool> verify(String artifactPath, {String? caFile}) async {
    final ProcessOutcome checked = await runner.run(executable, <String>[
      'verify',
      if (caFile != null) ...<String>['-CAfile', caFile],
      '-in',
      artifactPath,
    ]);
    return checked.succeeded;
  }
}
