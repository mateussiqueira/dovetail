import 'dart:io';

import 'package:dovetail_process_runner/dovetail_process_runner.dart';
import 'package:dovetail_signer/src/signing_failure.dart';
import 'package:dovetail_signer/src/update/update_signature.dart';
import 'package:path/path.dart' as p;

sealed class SecretKeyAccess {
  const SecretKeyAccess();
}

final class PasswordProtectedKey extends SecretKeyAccess {
  const PasswordProtectedKey(this.password);

  final String password;
}

final class UnencryptedKey extends SecretKeyAccess {
  const UnencryptedKey();
}

final class UpdateSigner {
  const UpdateSigner({required this.runner, this.minisign = 'minisign'});

  final ProcessRunner runner;
  final String minisign;

  Future<UpdateSignature> sign({
    required String artifactPath,
    required String secretKeyPath,
    required SecretKeyAccess access,
    String? trustedComment,
    String? untrustedComment,
    String? signaturePath,
  }) async {
    if (!File(artifactPath).existsSync()) {
      throw SigningFailure(
        'there is nothing to sign at $artifactPath.',
        remedy: 'Build and, on macOS, notarize the artefact first.',
      );
    }
    if (!File(secretKeyPath).existsSync()) {
      throw SigningFailure(
        'the update signing key is not at $secretKeyPath.',
        remedy:
            'It is the key every client already trusts. Losing it means no '
            'client accepts an update again, and it cannot be reissued '
            'without shipping a new installer to every machine.',
      );
    }
    if (access is PasswordProtectedKey && access.password.isEmpty) {
      throw const SigningFailure(
        'the key password is empty.',
        remedy:
            'An empty password is never assumed. If the key really has none, '
            'say so with UnencryptedKey.',
      );
    }

    final String destination =
        signaturePath ?? '$artifactPath$defaultSignatureExtension';

    final ProcessOutcome outcome = await runner.run(
      minisign,
      argumentsFor(
        artifactPath: artifactPath,
        secretKeyPath: secretKeyPath,
        signaturePath: destination,
        trustedComment: trustedComment,
        untrustedComment: untrustedComment,
      ),
      stdin: switch (access) {
        PasswordProtectedKey(password: final String password) => '$password\n',
        UnencryptedKey() => null,
      },
    );

    if (!outcome.succeeded) {
      throw SigningFailure(
        'minisign refused to sign ${p.basename(artifactPath)}.',
        remedy: _diagnostic(outcome),
      );
    }

    final File signature = File(destination);
    if (!signature.existsSync()) {
      throw SigningFailure(
        'minisign reported success but wrote no signature to $destination.',
        remedy:
            'An unsigned update that a release believes is signed is a '
            'release nobody can install.',
      );
    }

    return UpdateSignature(
      artifactPath: artifactPath,
      signaturePath: destination,
      content: signature.readAsStringSync(),
    );
  }

  List<String> argumentsFor({
    required String artifactPath,
    required String secretKeyPath,
    required String signaturePath,
    String? trustedComment,
    String? untrustedComment,
  }) => <String>[
    '-S',
    '-s',
    secretKeyPath,
    '-x',
    signaturePath,
    if (trustedComment != null) ...<String>['-t', trustedComment],
    if (untrustedComment != null) ...<String>['-c', untrustedComment],
    '-m',
    artifactPath,
  ];

  static const String defaultSignatureExtension = '.minisig';

  static String _diagnostic(ProcessOutcome outcome) {
    final String text = outcome.stderr.trim().isEmpty
        ? outcome.stdout
        : outcome.stderr;
    final Iterable<String> lines = text
        .split('\n')
        .map((String line) => line.trim())
        .where(
          (String line) =>
              line.isNotEmpty &&
              line != 'Password:' &&
              !line.startsWith('Deriving a key'),
        );
    return lines.isEmpty ? 'exit code ${outcome.exitCode}' : lines.join(' ');
  }
}
