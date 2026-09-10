import 'package:dovetail_privileged_helper/dovetail_privileged_helper.dart';
import 'package:flutter_test/flutter_test.dart';

/// The three questions a screen asks the state, and the answers that keep it
/// from drawing a button nobody can use.
void main() {
  group('mayRegister', () {
    test('should be true for notRegistered and for nothing else', () {
      for (final HelperState state in HelperState.values) {
        expect(
          state.mayRegister,
          state == HelperState.notRegistered,
          reason:
              'the exclusion that matters is requiresApproval: registering an '
              'already-registered daemon reports success on macOS and changes '
              'nothing, so a button wired to it looks broken and gets pressed '
              'again. That was the original defect: $state',
        );
      }
    });
  });

  group('canEverBeEnabled', () {
    test('should be false only where nothing anybody does would help', () {
      expect(HelperState.unsupported.canEverBeEnabled, false);
      expect(HelperState.blockedByPolicy.canEverBeEnabled, false);

      expect(
        HelperState.failed.canEverBeEnabled,
        true,
        reason:
            'a failure can be transient — a read that did not land, a service '
            'manager that was busy — and treating it as final would hide the '
            'retry from a person for whom retrying works',
      );
      expect(HelperState.notRegistered.canEverBeEnabled, true);
      expect(HelperState.requiresApproval.canEverBeEnabled, true);
      expect(HelperState.enabled.canEverBeEnabled, true);
    });
  });

  group('unsupported', () {
    test('should never look like a working helper', () {
      const HelperState state = HelperState.unsupported;

      expect(state.isEnabled, false);
      expect(state.mayRegister, false);
      expect(state.needsApproval, false);
      expect(
        state.canEverBeEnabled,
        false,
        reason:
            'a phone, a browser and a macOS 12 all arrive here. Every one of '
            'those answering anything other than "no" would put an install '
            'flow in front of somebody who has nothing to install',
      );
    });
  });

  group('the enum itself', () {
    test(
      'should keep unsupported first, so an unread state is not a promise',
      () {
        expect(
          HelperState.values.first,
          HelperState.unsupported,
          reason:
              'the safest state is the one a careless default lands on. First '
              'means an uninitialised read, an empty deserialisation and a '
              'values.first all say "this host does nothing" rather than '
              '"installed and running"',
        );
      },
    );
  });
}
