import 'package:dovetail_signer/src/policy/credential.dart';
import 'package:dovetail_signer/src/signing_failure.dart';

enum SigningDecision { sign, skip }

final class PolicyVerdict {
  const PolicyVerdict({required this.decision, required this.note});

  final SigningDecision decision;
  final String note;

  bool get shouldSign => decision == SigningDecision.sign;
}

final class SigningPolicy {
  const SigningPolicy({required this.requireSignature});

  final bool requireSignature;

  PolicyVerdict decide({
    required CredentialGroup group,
    required Map<String, String> environment,
  }) {
    if (group.isSatisfiedBy(environment)) {
      return PolicyVerdict(
        decision: SigningDecision.sign,
        note: '${group.label}: every credential is present.',
      );
    }

    final List<Credential> missing = group.missingIn(environment);
    final String names = missing.map((Credential c) => c.name).join(', ');

    if (group.isPartiallySatisfiedBy(environment)) {
      throw SigningFailure(
        '${group.label} is half configured: $names missing.',
        remedy:
            'A partial credential set is a misconfiguration, not a choice. '
            'Set the missing values or unset the ones that are there.',
      );
    }

    if (requireSignature) {
      throw SigningFailure(
        '${group.label} has no credentials and a signature was required.',
        remedy: 'Set $names, or drop --require-signature for a local build.',
      );
    }

    return PolicyVerdict(
      decision: SigningDecision.skip,
      note:
          '${group.label}: no credentials, so the artefact stays unsigned. '
          'Missing $names.',
    );
  }

  String requirePassword({
    required Map<String, String> environment,
    required String variable,
    required String label,
  }) {
    final String? value = environment[variable];
    if (value == null) {
      throw SigningFailure(
        '$label needs $variable and it is not set.',
        remedy:
            'Set it explicitly. An empty password is never assumed, not even '
            'in CI: a key generated without one would look protected and '
            'would not be.',
      );
    }
    return value;
  }
}
