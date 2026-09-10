import 'package:dovetail_privileged_helper/src/approval_pane.dart';
import 'package:dovetail_privileged_helper/src/helper_backend.dart';
import 'package:dovetail_privileged_helper/src/helper_state.dart';
import 'package:dovetail_privileged_helper/src/helper_status.dart';
import 'package:dovetail_privileged_helper/src/linux/systemd_unit_state.dart';
import 'package:dovetail_privileged_helper/src/privileged_helper.dart';
import 'package:dovetail_privileged_helper/src/registration_guard.dart';
import 'package:dovetail_process_runner/dovetail_process_runner.dart';

/// The Linux route: a systemd unit, authenticated through polkit.
///
/// No native code, and that is the whole of the design. Everything a C or C++
/// half could do here is spawn `systemctl` — the polkit dialog belongs to
/// `pkexec`, not to this package — and Dart spawns processes perfectly well.
/// Linking libsystemd to reach a program that is already on the PATH would be
/// a build dependency bought for nothing, and it would move the one part
/// worth testing out of reach of `flutter test`.
///
/// What that buys instead: every path below is exercised on this Mac with a
/// stand-in runner, which is more than the other two backends can say.
final class SystemdHelper implements PrivilegedHelper {
  /// A helper over [unitName], running `systemctl` through [runner].
  const SystemdHelper({required this.unitName, ProcessRunner? runner})
    : _runner = runner ?? const SystemProcessRunner();

  /// The unit, with its suffix — `example-helper.service`.
  final String unitName;

  final ProcessRunner _runner;

  @override
  HelperBackend get backend => HelperBackend.systemdUnit;

  @override
  ApprovalPane get approvalPane => ApprovalPane.noLinuxPane;

  @override
  Future<HelperStatus> status() async {
    final ProcessOutcome outcome;
    try {
      outcome = await _runner.run('systemctl', <String>[
        'is-enabled',
        unitName,
      ]);
    } on Object catch (error) {
      return HelperStatus(
        state: HelperState.failed,
        backend: HelperBackend.systemdUnit,
        detail:
            'systemctl could not be run, so nothing about $unitName is '
            'known: $error',
      );
    }

    // The exit code is discarded on purpose. `is-enabled` exits non-zero for
    // `disabled`, which is a healthy unit that is simply switched off, and a
    // reader that trusted the code would call that a failure.
    return SystemdUnitState.fromWord(
      outcome.stdout.split('\n').first,
      unitName: unitName,
      diagnostic: outcome.firstDiagnostic,
    );
  }

  @override
  Future<HelperStatus> register() async {
    final HelperStatus current = await status();
    return RegistrationGuard.refuseRegister(current) ??
        await _elevate(<String>['enable', '--now', unitName]);
  }

  @override
  Future<HelperStatus> unregister() async {
    final HelperStatus current = await status();
    return RegistrationGuard.refuseUnregister(current) ??
        await _elevate(<String>['disable', '--now', unitName]);
  }

  @override
  Future<ApprovalPaneOutcome> openApprovalSettings() async =>
      ApprovalPaneOutcome.absent;

  /// Runs `systemctl` under `pkexec` and reports what systemd says afterwards.
  ///
  /// The state always comes from a fresh read, never from the exit code. A
  /// dismissed polkit dialog, a missing authentication agent and a policy
  /// that denies the action all exit non-zero and all leave the unit exactly
  /// where it was, and only reading it again says where that is. What the
  /// exit code contributes is the sentence.
  Future<HelperStatus> _elevate(List<String> arguments) async {
    final ProcessOutcome outcome;
    try {
      outcome = await _runner.run('pkexec', <String>[
        'systemctl',
        ...arguments,
      ]);
    } on Object catch (error) {
      return (await status()).because(
        'pkexec could not be run, so nothing was changed: $error',
      );
    }
    if (outcome.succeeded) {
      return status();
    }
    return (await status()).because(
      'polkit did not authorise the change, and $unitName is as it was. It '
      'said: ${outcome.firstDiagnostic}',
    );
  }
}
