import 'package:dovetail_signer/dovetail_signer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final String bundle = p.join('stage', 'Example.app');
  final MacosSigningRequest request = MacosSigningRequest(
    bundlePath: bundle,
    identity: '-',
    appEntitlements: 'app.plist',
    entitlementsByRelativePath: const <String, String>{
      'Contents/Helpers/daemon': 'helper.plist',
    },
  );

  test('nested entitlement paths accept the host separators', () {
    expect(
      request.entitlementsFor(
        SignTarget(
          path: p.join(bundle, 'Contents', 'Helpers', 'daemon'),
          isExecutable: true,
        ),
      ),
      'helper.plist',
    );
  });

  test('equivalent bundle root paths retain application entitlements', () {
    expect(
      request.entitlementsFor(
        SignTarget(path: '$bundle${p.separator}.', isExecutable: true),
      ),
      'app.plist',
    );
  });

  test('an unknown component never receives application entitlements', () {
    expect(
      request.entitlementsFor(
        SignTarget(
          path: p.join(bundle, 'Contents', 'Helpers', 'other'),
          isExecutable: true,
        ),
      ),
      isNull,
    );
  });

  test('non executable targets never receive entitlements', () {
    expect(
      request.entitlementsFor(
        SignTarget(
          path: p.join(bundle, 'Contents', 'Helpers', 'daemon'),
          isExecutable: false,
        ),
      ),
      isNull,
    );
  });
}
