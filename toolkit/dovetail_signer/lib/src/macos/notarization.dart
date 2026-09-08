import 'package:dovetail_signer/src/policy/credential.dart';
import 'package:dovetail_signer/src/signing_failure.dart';

abstract final class NotarizationCredentials {
  static const CredentialGroup appleId = CredentialGroup(
    label: 'Apple ID notarisation',
    members: <Credential>[
      Credential(name: 'APPLE_ID', purpose: 'the Apple account that submits'),
      Credential(
        name: 'APPLE_PASSWORD',
        purpose: 'an app-specific password, never the account password',
      ),
      Credential(
        name: 'APPLE_TEAM_ID',
        purpose: 'the team the submission is billed to',
      ),
    ],
  );

  static const CredentialGroup apiKey = CredentialGroup(
    label: 'App Store Connect API key notarisation',
    members: <Credential>[
      Credential(name: 'APPLE_API_KEY_ID', purpose: 'the key id'),
      Credential(name: 'APPLE_API_ISSUER', purpose: 'the issuer id'),
      Credential(
        name: 'APPLE_API_KEY_PATH',
        purpose: 'path to the AuthKey .p8 file',
      ),
    ],
  );

  static const CredentialGroup identity = CredentialGroup(
    label: 'Developer ID signing identity',
    members: <Credential>[
      Credential(
        name: 'APPLE_SIGNING_IDENTITY',
        purpose: 'the Developer ID Application identity in the keychain',
      ),
    ],
  );
}

abstract final class NotarytoolArguments {
  static List<String> forAppleId(Map<String, String> environment) => <String>[
    '--apple-id',
    _required(environment, 'APPLE_ID', NotarizationCredentials.appleId),
    '--password',
    _required(environment, 'APPLE_PASSWORD', NotarizationCredentials.appleId),
    '--team-id',
    _required(environment, 'APPLE_TEAM_ID', NotarizationCredentials.appleId),
  ];

  static List<String> forApiKey(Map<String, String> environment) => <String>[
    '--key-id',
    _required(environment, 'APPLE_API_KEY_ID', NotarizationCredentials.apiKey),
    '--key',
    _required(
      environment,
      'APPLE_API_KEY_PATH',
      NotarizationCredentials.apiKey,
    ),
    '--issuer',
    _required(environment, 'APPLE_API_ISSUER', NotarizationCredentials.apiKey),
  ];

  static List<String>? forWhicheverIsConfigured(
    Map<String, String> environment,
  ) {
    if (NotarizationCredentials.appleId.isSatisfiedBy(environment)) {
      return forAppleId(environment);
    }
    if (NotarizationCredentials.apiKey.isSatisfiedBy(environment)) {
      return forApiKey(environment);
    }
    for (final CredentialGroup group in <CredentialGroup>[
      NotarizationCredentials.appleId,
      NotarizationCredentials.apiKey,
    ]) {
      if (group.isPartiallySatisfiedBy(environment)) {
        throw SigningFailure(
          '${group.label} is half configured: '
          '${group.missingIn(environment).join(', ')} '
          '${group.missingIn(environment).length == 1 ? 'is' : 'are'} unset.',
          remedy:
              'Half a credential set is a release that fails at the submission '
              'step, after the build has already been paid for. Set the rest, '
              'or unset the group.',
        );
      }
    }
    return null;
  }

  static String _required(
    Map<String, String> environment,
    String name,
    CredentialGroup group,
  ) {
    final String? value = environment[name];
    if (value == null || value.trim().isEmpty) {
      throw SigningFailure(
        '$name is not set, and ${group.label} needs it.',
        remedy:
            'Reading it as absent used to produce a null check operator crash '
            'with no name attached.',
      );
    }
    return value;
  }
}
