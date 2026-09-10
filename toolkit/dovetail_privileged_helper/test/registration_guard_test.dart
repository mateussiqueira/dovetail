import 'package:dovetail_privileged_helper/dovetail_privileged_helper.dart';
import 'package:flutter_test/flutter_test.dart';

HelperStatus _status(HelperState state, {String? detail}) => HelperStatus(
  state: state,
  backend: HelperBackend.launchDaemon,
  detail: detail,
);

void main() {
  group('refuseRegister', () {
    test('should let notRegistered through and stop everything else', () {
      for (final HelperState state in HelperState.values) {
        final HelperStatus? refusal = RegistrationGuard.refuseRegister(
          _status(state),
        );

        expect(
          refusal == null,
          state.mayRegister,
          reason:
              'the predicate a screen reads to decide whether to draw the '
              'button and the guard that decides whether pressing it does '
              'anything have to agree. Disagreeing is a button that appears '
              'and does nothing, which is the original defect wearing a '
              'different hat: $state',
        );
      }
    });

    test(
      'should say, for requiresApproval, that a second try changes nothing',
      () {
        final HelperStatus? refusal = RegistrationGuard.refuseRegister(
          _status(HelperState.requiresApproval),
        );

        expect(refusal, isNotNull);
        expect(
          refusal!.state,
          HelperState.requiresApproval,
          reason:
              'a refusal reports the state it refused from. Reporting a failure '
              'here would lose that the component is installed and one human '
              'action away from working',
        );
        expect(refusal.detail, contains('changes'));
      },
    );

    test('should keep the platform sentence when it refuses on unsupported', () {
      const String said = 'this macOS is older than 13';
      final HelperStatus? refusal = RegistrationGuard.refuseRegister(
        _status(HelperState.unsupported, detail: said),
      );

      expect(
        refusal?.detail,
        said,
        reason:
            'the platform already explained itself, and replacing that with a '
            'sentence written here would swap a specific reason for a generic '
            'one',
      );
    });

    test('should carry the reason forward when it refuses on policy', () {
      const String said = 'the start type is Disabled';
      final HelperStatus? refusal = RegistrationGuard.refuseRegister(
        _status(HelperState.blockedByPolicy, detail: said),
      );

      expect(refusal?.detail, contains(said));
    });
  });

  group('refuseUnregister', () {
    test('should allow taking out what is in, approved or not', () {
      expect(
        RegistrationGuard.refuseUnregister(_status(HelperState.enabled)),
        isNull,
      );
      expect(
        RegistrationGuard.refuseUnregister(
          _status(HelperState.requiresApproval),
        ),
        isNull,
        reason:
            'backing out of a half-finished install is exactly what somebody '
            'who never approved it wants, and the platform accepts it',
      );
    });

    test('should refuse when there is nothing registered to take out', () {
      final HelperStatus? refusal = RegistrationGuard.refuseUnregister(
        _status(HelperState.notRegistered),
      );

      expect(refusal, isNotNull);
      expect(refusal!.state, HelperState.notRegistered);
    });

    test('should refuse on a state it could not read', () {
      for (final HelperState state in <HelperState>[
        HelperState.failed,
        HelperState.blockedByPolicy,
        HelperState.unsupported,
      ]) {
        expect(
          RegistrationGuard.refuseUnregister(_status(state)),
          isNotNull,
          reason:
              'unregistering on top of an unread state reports an outcome '
              'nobody measured: $state',
        );
      }
    });
  });
}
