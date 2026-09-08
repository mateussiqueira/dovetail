import 'package:dovetail_signer/src/policy/credential.dart';

abstract final class OsslsigncodeCredentials {
  static const CredentialGroup keyPair = CredentialGroup(
    label: 'Authenticode signing without a Windows machine',
    members: <Credential>[
      Credential(
        name: 'WINDOWS_CERTIFICATE_FILE',
        purpose: 'a PEM certificate, or a PKCS#12 bundle',
      ),
      Credential(
        name: 'WINDOWS_TIMESTAMP_URL',
        purpose:
            'RFC3161 timestamp server, without which the signature '
            'dies when the certificate expires',
      ),
    ],
  );

  static const String privateKeyVariable = 'WINDOWS_PRIVATE_KEY_FILE';
  static const String passwordVariable = 'WINDOWS_CERTIFICATE_PASSWORD';
}
