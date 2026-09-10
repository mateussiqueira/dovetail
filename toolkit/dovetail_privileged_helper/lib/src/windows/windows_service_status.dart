import 'package:dovetail_privileged_helper/src/helper_backend.dart';
import 'package:dovetail_privileged_helper/src/helper_state.dart';
import 'package:dovetail_privileged_helper/src/helper_status.dart';

/// Translates what the service control manager returned into a
/// [HelperStatus].
///
/// Windows answers in Win32 error codes and a start type, and the reading of
/// them is here, in Dart, where a test can put any pair in and check what
/// comes out. The C++ beside it has never run on this machine; this has.
///
/// The state Windows never produces is [HelperState.requiresApproval]. There
/// is no such thing here: installing a service is an elevation prompt that
/// either succeeds or does not, so there is no "installed but waiting for a
/// human" to be in. Anything on this platform that claimed that state would
/// be inventing it.
abstract final class WindowsServiceStatus {
  /// `ERROR_SUCCESS`.
  static const int errorSuccess = 0;

  /// `ERROR_ACCESS_DENIED`.
  static const int errorAccessDenied = 5;

  /// `ERROR_SERVICE_DOES_NOT_EXIST`.
  static const int errorServiceDoesNotExist = 1060;

  /// `ERROR_SERVICE_EXISTS`.
  static const int errorServiceExists = 1073;

  /// `SERVICE_DISABLED`, the start type an administrator sets to forbid a
  /// service without deleting it.
  static const int startTypeDisabled = 4;

  /// The state for one reading of the control manager.
  ///
  /// A registered service that is merely stopped reads as
  /// [HelperState.enabled], and that is deliberate: this package answers
  /// whether the privileged component is allowed to run, never whether it is
  /// running at this instant. A demand-start service sits stopped for months
  /// and is in perfect health, and a screen that treated stopped as broken
  /// would offer a repair for nothing.
  static HelperStatus fromQuery({
    required int error,
    required int startType,
    required String serviceName,
  }) {
    if (error == errorServiceDoesNotExist) {
      return const HelperStatus(
        state: HelperState.notRegistered,
        backend: HelperBackend.windowsService,
      );
    }
    if (error == errorAccessDenied) {
      // Reading a service's configuration is unprivileged on a stock Windows
      // — the default security descriptor grants it to authenticated users.
      // A denial here means somebody tightened that descriptor on purpose,
      // which is the definition of the policy state and not of a failure to
      // retry.
      return HelperStatus(
        state: HelperState.blockedByPolicy,
        backend: HelperBackend.windowsService,
        detail:
            'the service control manager refused to let this process read '
            '$serviceName. Reading a service is unprivileged by default, so '
            'this machine has been configured to forbid it, and no retry '
            'from the app changes that.',
      );
    }
    if (error != errorSuccess) {
      return HelperStatus(
        state: HelperState.failed,
        backend: HelperBackend.windowsService,
        detail:
            'the service control manager returned Win32 error $error while '
            'reading $serviceName',
      );
    }
    if (startType == startTypeDisabled) {
      return HelperStatus(
        state: HelperState.blockedByPolicy,
        backend: HelperBackend.windowsService,
        detail:
            '$serviceName is installed and its start type is Disabled. Only '
            'an administrator can change that, in services.msc; starting it '
            'from here fails every time until they do.',
      );
    }
    return const HelperStatus(
      state: HelperState.enabled,
      backend: HelperBackend.windowsService,
    );
  }

  /// The state for a `CreateService` or `DeleteService` that did not succeed.
  ///
  /// [errorAccessDenied] reads as [HelperState.failed] here and as
  /// [HelperState.blockedByPolicy] in [fromQuery], and the asymmetry is the
  /// point: creating a service requires elevation on every Windows there is,
  /// so a denial is the ordinary answer for an app that is not elevated —
  /// which is nearly all of them. Calling that "forbidden by policy" would
  /// tell a user their organisation blocked something their installer does
  /// routinely.
  static HelperStatus fromWriteError({
    required int error,
    required String serviceName,
  }) {
    if (error == errorAccessDenied) {
      return const HelperStatus(
        state: HelperState.failed,
        backend: HelperBackend.windowsService,
        detail:
            'the service control manager denied access. Creating or deleting '
            'a service needs an elevated process, and an app started by a '
            "user is not one — on Windows this is the installer's work, not "
            "the running app's.",
      );
    }
    return HelperStatus(
      state: HelperState.failed,
      backend: HelperBackend.windowsService,
      detail:
          'the service control manager returned Win32 error $error for '
          '$serviceName',
    );
  }
}
