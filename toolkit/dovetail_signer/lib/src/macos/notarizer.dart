import 'dart:convert';

import 'package:dovetail_process_runner/dovetail_process_runner.dart';
import 'package:dovetail_signer/src/signing_failure.dart';
import 'package:path/path.dart' as p;

final class Notarizer {
  const Notarizer({
    required this.runner,
    this.ditto = 'ditto',
    this.xcrun = 'xcrun',
    this.submissionLimit = const Duration(minutes: 30),
  });

  final ProcessRunner runner;
  final Duration submissionLimit;
  final String ditto;
  final String xcrun;

  List<String> archiveArguments({
    required String bundlePath,
    required String archivePath,
  }) => <String>[
    '-c',
    '-k',
    '--keepParent',
    '--sequesterRsrc',
    bundlePath,
    archivePath,
  ];

  Future<void> notarize({
    required String bundlePath,
    required String archivePath,
    required List<String> credentialArguments,
  }) async {
    final ProcessOutcome archived = await runner.run(
      ditto,
      archiveArguments(bundlePath: bundlePath, archivePath: archivePath),
    );
    if (!archived.succeeded) {
      throw SigningFailure(
        'ditto failed to archive $bundlePath.',
        remedy:
            'ditto is used instead of zip because it produces an archive the '
            'notary service accepts; a plain zip raises false rejections.',
      );
    }

    await _submitAndStaple(
      submission: archivePath,
      stapleTarget: bundlePath,
      credentialArguments: credentialArguments,
    );
  }

  /// Um arquivo plano — o `.dmg` — vai direto ao notary service, sem `ditto`:
  /// o servico aceita a imagem como esta, e o ticket e grampeado nela mesma.
  /// E a imagem, nao o `.app` solto, que o usuario baixa e o Gatekeeper abre.
  Future<void> notarizeFile({
    required String path,
    required List<String> credentialArguments,
  }) => _submitAndStaple(
    submission: path,
    stapleTarget: path,
    credentialArguments: credentialArguments,
  );

  Future<void> _submitAndStaple({
    required String submission,
    required String stapleTarget,
    required List<String> credentialArguments,
  }) async {
    final ProcessOutcome submitted = await runner.run(xcrun, <String>[
      'notarytool',
      'submit',
      submission,
      '--output-format',
      'json',
      '--wait',
      ...credentialArguments,
    ], timeout: submissionLimit);
    if (!submitted.succeeded) {
      throw SigningFailure(
        'notarytool submit failed with exit code ${submitted.exitCode}.',
        remedy: submitted.stderr.trim().isEmpty
            ? submitted.stdout.trim()
            : submitted.stderr.trim(),
      );
    }

    final String status = _statusOf(submitted.stdout);
    if (status != 'Accepted') {
      throw SigningFailure(
        'the notary service answered "$status" instead of "Accepted".',
        remedy: 'Read the log with: xcrun notarytool log <submission-id>',
      );
    }

    final ProcessOutcome stapled = await runner.run(xcrun, <String>[
      'stapler',
      'staple',
      '-v',
      p.basename(stapleTarget),
    ], workingDirectory: p.dirname(stapleTarget));
    if (!stapled.succeeded) {
      throw SigningFailure(
        'stapler failed to attach the ticket to $stapleTarget.',
        remedy:
            'Without a stapled ticket the app needs the network on first '
            'launch to pass Gatekeeper.',
      );
    }
  }

  String _statusOf(String output) {
    try {
      final Object? parsed = jsonDecode(output);
      if (parsed is Map<String, Object?>) {
        return parsed['status']?.toString() ?? 'unknown';
      }
    } on FormatException {
      return 'unparseable';
    }
    return 'unknown';
  }
}
