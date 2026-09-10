import 'package:dovetail_privileged_helper/src/helper_state.dart';
import 'package:dovetail_privileged_helper/src/helper_status.dart';

/// Decides whether a registration call is worth making at all.
///
/// The one place the defect this package was written for is fixed, and it is
/// shared by all three backends because all three could make it. A product
/// that asked only "is it installed?" wired its install button straight to the
/// platform on every answer that was not yes — including the answer where the
/// platform accepts the call, reports success, and does nothing, because what
/// is missing is a human decision taken in another application.
///
/// Both methods answer null for "go ahead" and a status for "do not", so the
/// caller reads as a guard clause and a refusal reaches the screen as the same
/// kind of value every other call returns.
abstract final class RegistrationGuard {
  /// The status to return instead of registering, or null to register.
  ///
  /// Answers null exactly when [HelperState.mayRegister] is true, and there
  /// is a test holding those two together: the predicate is what a screen
  /// reads to decide whether to draw the button, and this is what decides
  /// whether pressing it does anything. They disagreeing is a button that
  /// appears and does nothing, which is the original defect wearing a
  /// different hat.
  static HelperStatus? refuseRegister(
    HelperStatus current,
  ) => switch (current.state) {
    HelperState.notRegistered => null,
    HelperState.requiresApproval => current.because(
      'nothing was sent to the system: the component is registered '
      'already and is waiting for somebody to approve it outside this '
      'app. Registering it a second time reports success and changes '
      'nothing, which is why this refuses instead.',
    ),
    HelperState.enabled => current.because(
      'nothing was sent to the system: the component is installed and '
      'permitted to run.',
    ),
    HelperState.blockedByPolicy => current.because(
      'nothing was sent to the system: this host forbids the component by '
              'policy, and a registration would be refused however often it is '
              'tried. ${current.detail ?? ''}'
          .trimRight(),
    ),
    HelperState.unsupported => current,
    HelperState.failed => current.because(
      'nothing was sent to the system: the last read of the component '
              'failed, and registering on top of an unread state would report an '
              'outcome nobody measured. ${current.detail ?? ''}'
          .trimRight(),
    ),
  };

  /// The status to return instead of unregistering, or null to unregister.
  ///
  /// Deliberately more permissive than [refuseRegister]: it lets
  /// [HelperState.requiresApproval] through, because taking out a component
  /// the user never approved is exactly what somebody backing out of a
  /// half-finished install wants, and the platform accepts it.
  static HelperStatus? refuseUnregister(HelperStatus current) =>
      switch (current.state) {
        HelperState.enabled || HelperState.requiresApproval => null,
        HelperState.notRegistered => current.because(
          'nothing was sent to the system: there is no component registered '
          'to take out.',
        ),
        HelperState.unsupported => current,
        HelperState.blockedByPolicy || HelperState.failed => current.because(
          'nothing was sent to the system: the component could not be read, '
                  'so there is no knowing what an unregistration would act on. '
                  '${current.detail ?? ''}'
              .trimRight(),
        ),
      };
}
