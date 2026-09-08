import 'package:dovetail_signer/src/signing_failure.dart';

final class OsslsigncodeRequest {
  const OsslsigncodeRequest({
    required this.certificatePath,
    required this.timestampUrl,
    this.privateKeyPath,
    this.password,
    this.digestAlgorithm = 'sha256',
    this.programName,
    this.programUrl,
  });

  final String certificatePath;
  final String? privateKeyPath;
  final String? password;
  final String timestampUrl;
  final String digestAlgorithm;
  final String? programName;
  final String? programUrl;

  bool get isKeyPair => privateKeyPath != null;

  List<String> credentialArguments() {
    if (certificatePath.trim().isEmpty) {
      throw const SigningFailure(
        'no certificate was given.',
        remedy:
            'osslsigncode takes either a PEM certificate with its key, or a '
            'PKCS#12 bundle with its password. Neither is guessed.',
      );
    }

    final String? key = privateKeyPath;
    if (key != null) {
      if (key.trim().isEmpty) {
        throw const SigningFailure(
          'the private key path is blank.',
          remedy:
              'A blank path reads as a PKCS#12 bundle, and the certificate '
              'would be handed to the wrong flag.',
        );
      }
      return <String>['-certs', certificatePath, '-key', key];
    }

    final String? secret = password;
    if (secret == null || secret.isEmpty) {
      throw const SigningFailure(
        'a PKCS#12 bundle was given with no password.',
        remedy:
            'An empty password is never assumed. osslsigncode prompts on a '
            'terminal and hangs without one, which in a pipeline reads as a '
            'build that never finishes.',
      );
    }
    return <String>['-pkcs12', certificatePath, '-pass', secret];
  }
}
