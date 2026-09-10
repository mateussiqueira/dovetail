import 'package:dovetail_privileged_helper/src/darwin/darwin_helper_route.dart';

/// The names by which each operating system knows one app's privileged
/// component.
///
/// Three names and not one, because the three systems identify the thing
/// differently and no single string is honest on all of them: macOS wants the
/// file name of a property list inside the bundle, Windows a service name in
/// the control manager's registry, Linux a unit name systemd will match.
///
/// All three are required even for an app that ships on one platform. A spec
/// that carried nulls would push the "which platform am I on" branch into
/// every caller, which is the branching this package exists to remove.
final class HelperSpec {
  /// A spec naming the same component on all three desktops.
  const HelperSpec({
    required this.macOSDaemonPlist,
    required this.windowsServiceName,
    required this.linuxUnitName,
    this.windowsServiceImagePath,
    this.windowsServiceDisplayName,
    this.macOSRoute = DarwinHelperRoute.privilegedDaemon,
  });

  /// The property list under `Contents/Library/LaunchDaemons`, with its
  /// extension — `com.example.app.helper.plist`.
  ///
  /// The file name, not a path and not a label: `SMAppService` looks it up
  /// inside the calling bundle, and a name that is not there reports as a
  /// failure rather than as "not installed", because rebuilding the app is
  /// the fix and installing is not.
  final String macOSDaemonPlist;

  /// The service name the control manager knows, which is not the display
  /// name a user sees in `services.msc`.
  final String windowsServiceName;

  /// The systemd unit, with its suffix — `example-helper.service`.
  final String linuxUnitName;

  /// The binary the control manager should run, when this app installs its
  /// own service.
  ///
  /// Null is the ordinary case and not an omission: on Windows the installer
  /// creates the service, because creating one needs an elevated process and
  /// the app is not one. With this null, `register` refuses and says that,
  /// instead of calling the control manager and reporting an access denial
  /// the caller cannot interpret.
  final String? windowsServiceImagePath;

  /// What `services.msc` should show. Null uses [windowsServiceName], which
  /// the control manager requires to be non-empty.
  final String? windowsServiceDisplayName;

  /// Which macOS route to take. See [DarwinHelperRoute].
  final DarwinHelperRoute macOSRoute;
}
