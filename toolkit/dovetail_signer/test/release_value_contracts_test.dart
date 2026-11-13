import 'package:dovetail_signer/dovetail_signer.dart';
import 'package:test/test.dart';

void main() {
  SignTarget target(String path, bool executable) =>
      SignTarget(path: path, isExecutable: executable);
  Credential credential(String name, String purpose) =>
      Credential(name: name, purpose: purpose);

  test('signing targets distinguish path and executable status in sets', () {
    final SignTarget original = target('client', true);
    expect(<SignTarget>{original}.contains(target('client', true)), true);
    expect(original, isNot(target('other', true)));
    expect(original, isNot(target('client', false)));
    expect(original, isNot(Object()));
    expect(original.toString(), 'SignTarget(client, executable: true)');
  });

  test(
    'credential identity uses its environment name rather than its purpose',
    () {
      final Credential original = credential('SIGN_ID', 'first purpose');
      expect(
        <Credential>{original}.contains(credential('SIGN_ID', 'other purpose')),
        true,
      );
      expect(original, isNot(credential('OTHER_ID', 'first purpose')));
      expect(original, isNot(Object()));
      expect(original.toString(), 'SIGN_ID');
    },
  );

  test(
    'a signing request distinguishes a PEM key pair from a certificate bundle',
    () {
      const OsslsigncodeRequest pair = OsslsigncodeRequest(
        certificatePath: 'certificate.pem',
        privateKeyPath: 'key.pem',
        timestampUrl: 'https://example.test',
      );
      const OsslsigncodeRequest bundle = OsslsigncodeRequest(
        certificatePath: 'bundle.pfx',
        timestampUrl: 'https://example.test',
      );
      expect(pair.isKeyPair, true);
      expect(bundle.isKeyPair, false);
    },
  );
}
