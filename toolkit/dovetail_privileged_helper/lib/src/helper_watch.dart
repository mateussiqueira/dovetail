import 'package:dovetail_privileged_helper/src/helper_status.dart';
import 'package:dovetail_privileged_helper/src/privileged_helper.dart';

/// Re-reads the helper's status whenever something says the world may have
/// changed.
///
/// The piece everybody forgets. The approval happens in System Settings, not
/// in this app: the person leaves, switches the daemon on, comes back — and an
/// app that read the status once at launch still says "not approved", until
/// somebody restarts it. Reported as a bug against the app, every time.
///
/// The trigger is passed in rather than found here, because this package does
/// not own the window. `dovetail_platform_channel` does, and an app that uses
/// it hands in its focus stream; an app that does not can hand in an
/// `AppLifecycleListener`, a timer, or a refresh button. What matters is that
/// the re-read happens at all.
final class HelperWatch {
  /// A watch over [helper].
  const HelperWatch(this.helper);

  /// The helper being re-read.
  final PrivilegedHelper helper;

  /// The status now, and again after each event on [triggers].
  ///
  /// Only changes are emitted. A window that gains focus forty times in a
  /// session where nothing was approved should not push forty identical
  /// rebuilds through a UI, and a caller that wants the current value
  /// regardless has `PrivilegedHelper.status` for exactly that.
  Stream<HelperStatus> refreshedOn(Stream<void> triggers) async* {
    HelperStatus last = await helper.status();
    yield last;
    await for (final _ in triggers) {
      final HelperStatus fresh = await helper.status();
      if (fresh != last) {
        last = fresh;
        yield fresh;
      }
    }
  }
}
