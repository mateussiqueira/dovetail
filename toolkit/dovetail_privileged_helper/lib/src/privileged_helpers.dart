import 'package:dovetail_privileged_helper/src/darwin/darwin_daemon_helper.dart';
import 'package:dovetail_privileged_helper/src/darwin/darwin_helper_route.dart';
import 'package:dovetail_privileged_helper/src/helper_host.dart';
import 'package:dovetail_privileged_helper/src/helper_spec.dart';
import 'package:dovetail_privileged_helper/src/linux/systemd_helper.dart';
import 'package:dovetail_privileged_helper/src/privileged_helper.dart';
import 'package:dovetail_privileged_helper/src/unsupported_helper.dart';
import 'package:dovetail_privileged_helper/src/windows/windows_service_helper.dart';

/// Picks the helper for a host.
///
/// The one place in this package that branches on the operating system, which
/// is the point: a caller names [PrivilegedHelper] and never asks which system
/// it is on. Every branch ends in a helper — never in null and never in a
/// throw — so a screen written against the interface renders on a phone as
/// readily as on a Mac, and says something true there.
abstract final class PrivilegedHelpers {
  /// The helper for [spec] on [host], defaulting to the host this process
  /// runs on.
  ///
  /// The macOS version is not checked here, and deliberately: `SMAppService`
  /// arrived in macOS 13, and the only reading of that worth trusting is the
  /// availability check compiled into the Objective-C. Deciding it in Dart
  /// would mean parsing `Platform.operatingSystemVersion`, which is a
  /// human-readable string that Apple has changed the shape of before. On an
  /// older macOS the helper below is built and its first answer is
  /// `HelperState.unsupported`, from the platform rather than from a guess.
  static PrivilegedHelper of(HelperSpec spec, {HelperHost? host}) =>
      switch (host ?? HelperHost.current()) {
        HelperHost.macos => switch (spec.macOSRoute) {
          DarwinHelperRoute.privilegedDaemon => DarwinDaemonHelper(
            plistName: spec.macOSDaemonPlist,
          ),
          DarwinHelperRoute.networkExtension => const UnsupportedHelper(
            'this package does not implement the Network Extension route. It '
            'is the only way onto the Mac App Store and it needs an '
            'entitlement Apple grants per application, so a toolkit cannot '
            'promise it — and installing a privileged daemon instead, '
            'quietly, would give the caller a product they did not ask for. '
            'ARCHITECTURE.md carries the comparison.',
          ),
        },
        HelperHost.windows => WindowsServiceHelper(
          serviceName: spec.windowsServiceName,
          displayName: spec.windowsServiceDisplayName,
          imagePath: spec.windowsServiceImagePath,
        ),
        HelperHost.linux => SystemdHelper(unitName: spec.linuxUnitName),
        HelperHost.other => const UnsupportedHelper(
          'this platform runs no privileged component alongside the app: '
          'there is nothing to install, and nobody to ask.',
        ),
      };
}
