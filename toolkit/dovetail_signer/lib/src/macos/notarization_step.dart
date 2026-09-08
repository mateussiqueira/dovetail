import 'package:dovetail_signer/src/macos/notarization.dart';
import 'package:dovetail_signer/src/macos/notarizer.dart';
import 'package:dovetail_process_runner/dovetail_process_runner.dart';

enum NotarizationOutcome { notarised, noCredentials }

final class NotarizationStep {
  const NotarizationStep({required this.runner, this.notarizer});

  final ProcessRunner runner;
  final Notarizer? notarizer;

  Future<NotarizationOutcome> run({
    required String bundlePath,
    required Map<String, String> environment,
    String? archivePath,
  }) async {
    final List<String>? credentials =
        NotarytoolArguments.forWhicheverIsConfigured(environment);
    if (credentials == null) {
      return NotarizationOutcome.noCredentials;
    }

    await (notarizer ?? Notarizer(runner: runner)).notarize(
      bundlePath: bundlePath,
      archivePath: archivePath ?? '$bundlePath.zip',
      credentialArguments: credentials,
    );
    return NotarizationOutcome.notarised;
  }

  /// O mesmo veredito de credenciais, para um arquivo plano — o `.dmg`.
  Future<NotarizationOutcome> runOnFile({
    required String path,
    required Map<String, String> environment,
  }) async {
    final List<String>? credentials =
        NotarytoolArguments.forWhicheverIsConfigured(environment);
    if (credentials == null) {
      return NotarizationOutcome.noCredentials;
    }

    await (notarizer ?? Notarizer(runner: runner)).notarizeFile(
      path: path,
      credentialArguments: credentials,
    );
    return NotarizationOutcome.notarised;
  }
}
