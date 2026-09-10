import 'package:dovetail_privileged_helper/src/approval_pane.dart';
import 'package:dovetail_privileged_helper/src/helper_backend.dart';
import 'package:dovetail_privileged_helper/src/helper_state.dart';
import 'package:dovetail_privileged_helper/src/helper_status.dart';
import 'package:dovetail_privileged_helper/src/privileged_helper.dart';
import 'package:dovetail_privileged_helper/src/registration_guard.dart';
import 'package:dovetail_privileged_helper/src/windows/windows_service_control.dart';
import 'package:dovetail_privileged_helper/src/windows/windows_service_status.dart';

/// The Windows route: a service in the control manager.
///
/// The flow has one state fewer than the macOS one, and pretending otherwise
/// would be the whole mistake this package exists to avoid. Windows asks for
/// elevation when the service is created, gets an answer there and then, and
/// keeps no "installed but not yet approved" state for anything to sit in.
/// What it does keep is a start type an administrator can set to Disabled,
/// which is the policy state, and there is no pane to send anybody to for it.
final class WindowsServiceHelper implements PrivilegedHelper {
  /// A helper over the service named [serviceName].
  ///
  /// [imagePath] is the binary the control manager should run, and null — the
  /// ordinary case — means this app does not install its own service and
  /// [register] will say so rather than call into a denial.
  WindowsServiceHelper({
    required this.serviceName,
    this.displayName,
    this.imagePath,
    WindowsServiceControl? control,
  }) : _control = control ?? WindowsServiceControl();

  /// The name the control manager knows.
  final String serviceName;

  /// What `services.msc` shows; [serviceName] when null.
  final String? displayName;

  /// The binary to register, or null when the installer owns that.
  final String? imagePath;

  final WindowsServiceControl _control;

  @override
  HelperBackend get backend => HelperBackend.windowsService;

  @override
  ApprovalPane get approvalPane => ApprovalPane.noWindowsPane;

  @override
  Future<HelperStatus> status() async {
    if (!_control.isAvailable) {
      return const HelperStatus(
        state: HelperState.failed,
        backend: HelperBackend.windowsService,
        detail:
            'dovetail_privileged_helper.dll did not load, so the service '
            'control manager was never asked. In a widget test that is '
            'expected; in a built app it means the plugin did not make it '
            'into the runner.',
      );
    }
    final WindowsServiceReading reading = _control.query(serviceName);
    return WindowsServiceStatus.fromQuery(
      error: reading.error,
      startType: reading.startType,
      serviceName: serviceName,
    );
  }

  @override
  Future<HelperStatus> register() async {
    final HelperStatus current = await status();
    final HelperStatus? refused = RegistrationGuard.refuseRegister(current);
    if (refused != null) {
      return refused;
    }

    final String? binary = imagePath;
    if (binary == null) {
      return current.because(
        'nothing was sent to the control manager: this app was not given a '
        'binary to register. Creating a service needs an elevated process, so '
        'on Windows the installer normally does it, and an app that tries '
        'gets an access denial it cannot act on.',
      );
    }

    final int error = _control.create(
      name: serviceName,
      displayName: displayName ?? serviceName,
      imagePath: binary,
    );
    if (error != WindowsServiceStatus.errorSuccess &&
        error != WindowsServiceStatus.errorServiceExists) {
      return WindowsServiceStatus.fromWriteError(
        error: error,
        serviceName: serviceName,
      );
    }
    // Re-read rather than assume: a service created with a start type an
    // administrator's policy overrides comes back Disabled, and reporting
    // "enabled" off the back of a successful CreateService would be the
    // package telling the user something it never measured.
    return status();
  }

  @override
  Future<HelperStatus> unregister() async {
    final HelperStatus current = await status();
    final HelperStatus? refused = RegistrationGuard.refuseUnregister(current);
    if (refused != null) {
      return refused;
    }

    final int error = _control.delete(serviceName);
    if (error != WindowsServiceStatus.errorSuccess) {
      return WindowsServiceStatus.fromWriteError(
        error: error,
        serviceName: serviceName,
      );
    }
    return status();
  }

  @override
  Future<ApprovalPaneOutcome> openApprovalSettings() async =>
      ApprovalPaneOutcome.absent;
}
