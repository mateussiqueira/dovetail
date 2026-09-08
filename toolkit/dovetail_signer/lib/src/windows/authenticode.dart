import 'package:dovetail_signer/src/policy/credential.dart';
import 'package:dovetail_process_runner/dovetail_process_runner.dart';
import 'package:dovetail_signer/src/signing_failure.dart';

abstract final class AuthenticodeCredentials {
  static const CredentialGroup thumbprint = CredentialGroup(
    label: 'Authenticode signing',
    members: <Credential>[
      Credential(
        name: 'WINDOWS_CERTIFICATE_THUMBPRINT',
        purpose: 'SHA1 thumbprint of a certificate already in the store',
      ),
      Credential(
        name: 'WINDOWS_TIMESTAMP_URL',
        purpose:
            'RFC3161 timestamp server, without which the signature '
            'dies when the certificate expires',
      ),
    ],
  );
}

final class AuthenticodeRequest {
  const AuthenticodeRequest({
    required this.thumbprint,
    required this.timestampUrl,
    this.digestAlgorithm = 'sha256',
  });

  final String thumbprint;
  final String timestampUrl;
  final String digestAlgorithm;
}

final class Authenticode {
  const Authenticode({required this.runner, this.signtool = 'signtool'});

  final ProcessRunner runner;
  final String signtool;

  List<String> argumentsFor(AuthenticodeRequest request, String file) {
    if (request.thumbprint.trim().isEmpty) {
      throw const SigningFailure(
        'the certificate thumbprint is empty.',
        remedy:
            'An assert was guarding this, and an assert is not compiled into a '
            'release build. signtool would be handed /sha1 with nothing after '
            'it and would pick whatever certificate it finds first, or none.',
      );
    }
    if (request.digestAlgorithm.trim().isEmpty) {
      throw const SigningFailure(
        'no digest algorithm was given.',
        remedy: 'signtool would read the next flag as the algorithm name.',
      );
    }
    if (request.timestampUrl.trim().isEmpty) {
      throw const SigningFailure(
        'no timestamp server was given.',
        remedy:
            'A signature without a timestamp becomes invalid the day the '
            'certificate expires. There is no default here on purpose.',
      );
    }

    return <String>[
      'sign',
      '/fd',
      request.digestAlgorithm,
      '/sha1',
      request.thumbprint,
      '/tr',
      request.timestampUrl,
      '/td',
      request.digestAlgorithm,
      file,
    ];
  }

  Future<void> signAll({
    required AuthenticodeRequest request,
    required List<String> files,
  }) async {
    if (files.isEmpty) {
      throw const SigningFailure(
        'no file was given to sign.',
        remedy:
            'Signing nothing and reporting success is how an unsigned helper '
            'reaches a customer.',
      );
    }

    for (final String file in files) {
      final ProcessOutcome outcome = await runner.run(
        signtool,
        argumentsFor(request, file),
      );
      if (!outcome.succeeded) {
        throw SigningFailure(
          'signtool failed on $file with exit code ${outcome.exitCode}.',
          remedy: outcome.stderr.trim().isEmpty
              ? outcome.stdout.trim()
              : outcome.stderr.trim(),
        );
      }
    }
  }
}
