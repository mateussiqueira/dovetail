import 'package:dovetail_privileged_helper/dovetail_privileged_helper.dart';
import 'package:flutter_test/flutter_test.dart';

const String _plist = 'com.example.app.helper.plist';

/// The table the Objective-C and this Dart have to count the same way.
///
/// The four numbers are `SMAppService.Status`. One of them changing meaning on
/// either side is an app that offers to install a daemon that is already
/// there, on somebody else's Mac and nowhere here.
void main() {
  group('the raw status', () {
    test('should map the four Apple declares', () {
      HelperState read(int raw) =>
          DarwinServiceStatus.fromRaw(raw, plistName: _plist).state;

      expect(read(0), HelperState.notRegistered);
      expect(read(1), HelperState.enabled);
      expect(read(2), HelperState.requiresApproval);
      expect(
        read(3),
        HelperState.failed,
        reason:
            'notFound is a property list missing from the app bundle, which '
            'is a packaging fault. Reading it as notRegistered would offer an '
            'install that cannot work until the app is rebuilt',
      );
    });

    test('should read a number it does not know as a failure, not as an '
        'invitation to install', () {
      for (final int stranger in <int>[-1, 4, 99]) {
        expect(
          DarwinServiceStatus.fromRaw(stranger, plistName: _plist).state,
          HelperState.failed,
          reason:
              'a macOS newer than this package could add a fifth status. '
              'Offering to install something whose real state was never read '
              'is how a screen lies with confidence: $stranger',
        );
      }
    });

    test('should name the property list when it is the property list that is '
        'wrong', () {
      final HelperStatus status = DarwinServiceStatus.fromRaw(
        3,
        plistName: _plist,
      );

      expect(status.detail, contains(_plist));
    });

    test('should say, on requiresApproval, where the switch is', () {
      final HelperStatus status = DarwinServiceStatus.fromRaw(
        2,
        plistName: _plist,
      );

      expect(
        status.detail,
        contains('Login Items'),
        reason:
            'this is the only state where the app cannot finish the job, so '
            'the sentence has to name the place the person has to go',
      );
    });
  });

  group('the reply from the channel', () {
    test(
      'should report unsupported when macOS says it has no SMAppService',
      () {
        final HelperStatus status = DarwinServiceStatus.fromReply(
          <Object?, Object?>{'unsupported': 'this macOS is older than 13'},
          plistName: _plist,
        );

        expect(status.state, HelperState.unsupported);
        expect(status.backend, HelperBackend.none);
        expect(status.detail, 'this macOS is older than 13');
      },
    );

    test('should keep the status when a call failed and the status was still '
        'readable', () {
      final HelperStatus status = DarwinServiceStatus.fromReply(
        <Object?, Object?>{'raw': 2, 'error': 'Operation not permitted'},
        plistName: _plist,
      );

      expect(
        status.state,
        HelperState.requiresApproval,
        reason:
            'a registration can fail while the daemon is already registered. '
            'Reporting only the failure would lose that it is there, and the '
            'screen would offer an install for something installed',
      );
      expect(status.detail, 'Operation not permitted');
    });

    test('should fail, with the reason, when there is no status at all', () {
      final HelperStatus status = DarwinServiceStatus.fromReply(
        <Object?, Object?>{'error': 'the bundle is not signed'},
        plistName: _plist,
      );

      expect(status.state, HelperState.failed);
      expect(status.detail, 'the bundle is not signed');
    });

    test('should refuse to read a reply that is not a map', () {
      for (final Object? nonsense in <Object?>[null, 3, 'enabled']) {
        expect(
          DarwinServiceStatus.fromReply(nonsense, plistName: _plist).state,
          HelperState.failed,
          reason:
              'the wire is the one place a rename on the native side shows '
              'up, and it shows up as a shape that does not parse: $nonsense',
        );
      }
    });
  });
}
