import 'package:dovetail_signer/dovetail_signer.dart';
import 'package:test/test.dart';

const CredentialGroup _group = CredentialGroup(
  label: 'Example signing',
  members: <Credential>[
    Credential(name: 'A_KEY', purpose: 'the key'),
    Credential(name: 'A_SECRET', purpose: 'the secret'),
  ],
);

void main() {
  test('a complete credential set should sign', () {
    const SigningPolicy sut = SigningPolicy(requireSignature: false);

    final PolicyVerdict verdict = sut.decide(
      group: _group,
      environment: const <String, String>{'A_KEY': 'k', 'A_SECRET': 's'},
    );

    expect(verdict.shouldSign, true);
  });

  test('no credentials on a local build should skip and say so', () {
    const SigningPolicy sut = SigningPolicy(requireSignature: false);

    final PolicyVerdict verdict = sut.decide(
      group: _group,
      environment: const <String, String>{},
    );

    expect(verdict.shouldSign, false);
    expect(verdict.note, contains('stays unsigned'));
    expect(verdict.note, contains('A_KEY'));
  });

  test('no credentials with a required signature should be fatal', () {
    const SigningPolicy sut = SigningPolicy(requireSignature: true);

    expect(
      () => sut.decide(group: _group, environment: const <String, String>{}),
      throwsA(
        isA<SigningFailure>().having(
          (SigningFailure failure) => failure.message,
          'message',
          contains('a signature was required'),
        ),
      ),
    );
  });

  test('a half configured set should be fatal even on a local build', () {
    const SigningPolicy sut = SigningPolicy(requireSignature: false);

    expect(
      () => sut.decide(
        group: _group,
        environment: const <String, String>{'A_KEY': 'k'},
      ),
      throwsA(
        isA<SigningFailure>().having(
          (SigningFailure failure) => failure.message,
          'message',
          contains('half configured'),
        ),
      ),
      reason:
          'Tauri warns and continues here, producing artefacts no client '
          'accepts; a partial set is a misconfiguration, not a choice',
    );
  });

  test('a blank value should count as missing, not as present', () {
    const SigningPolicy sut = SigningPolicy(requireSignature: true);

    expect(
      () => sut.decide(
        group: _group,
        environment: const <String, String>{'A_KEY': '  ', 'A_SECRET': '  '},
      ),
      throwsA(isA<SigningFailure>()),
    );
  });

  test('an unset password should be fatal instead of assumed empty', () {
    const SigningPolicy sut = SigningPolicy(requireSignature: true);

    expect(
      () => sut.requirePassword(
        environment: const <String, String>{},
        variable: 'A_PASSWORD',
        label: 'Example',
      ),
      throwsA(
        isA<SigningFailure>().having(
          (SigningFailure failure) => failure.remedy,
          'remedy',
          contains('never assumed'),
        ),
      ),
      reason:
          'Tauri assumes an empty password when CI is set, so a key generated '
          'without one looks protected and is not',
    );
  });

  test('a deliberately empty password should be accepted when set', () {
    const SigningPolicy sut = SigningPolicy(requireSignature: true);

    expect(
      sut.requirePassword(
        environment: const <String, String>{'A_PASSWORD': ''},
        variable: 'A_PASSWORD',
        label: 'Example',
      ),
      '',
    );
  });

  test('every failure should carry a remedy', () {
    const SigningPolicy sut = SigningPolicy(requireSignature: true);

    try {
      sut.decide(group: _group, environment: const <String, String>{});
      fail('expected a SigningFailure');
    } on SigningFailure catch (failure) {
      expect(failure.remedy, isNotNull);
      expect(failure.toString(), contains('--require-signature'));
    }
  });
}
