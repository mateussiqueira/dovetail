import 'package:dovetail_shortcut_channel/src/shortcut_backend.dart';
import 'package:dovetail_shortcut_channel/src/shortcut_policy.dart';

/// What this session can do about system-wide shortcuts, decided before any native call.
final class ShortcutSupport {
  /// Support as the probe found it.
  const ShortcutSupport({
    required this.backend,
    required this.available,
    required this.applicationChoosesChord,
    required this.userMayRebind,
    required this.needsSystemPermission,
    required this.unavailableBecause,
    this.sessionName,
  });

  /// The facility in use, or [ShortcutBackend.none].
  final ShortcutBackend backend;

  /// Whether a chord can be bound at all in this session.
  final bool available;

  /// Whether the application picks the chord, as opposed to the desktop letting the user choose one.
  final bool applicationChoosesChord;

  /// Whether the user can change the chord outside the application, as a Wayland portal allows.
  final bool userMayRebind;

  /// Whether the system asks the user before granting the shortcut.
  final bool needsSystemPermission;

  /// When not [available], the sentence that says why — ready to show.
  final String? unavailableBecause;

  /// The desktop session on Linux (`XDG_CURRENT_DESKTOP`), when known.
  final String? sessionName;
}

/// Reads the environment and says which shortcut facility this session offers.
///
/// Pure: takes the host and the environment map, so a test can describe any session.
final class SessionProbe {
  /// A probe of [environment] on [host].
  const SessionProbe({required this.host, required this.environment});

  /// The operating system.
  final ShortcutHost host;

  /// The process environment, or a stand-in for it.
  final Map<String, String> environment;

  /// The support this session offers. On Linux, distinguishes X11 from Wayland and from no display at all.
  ShortcutSupport probe() => switch (host) {
    ShortcutHost.windows => const ShortcutSupport(
      backend: ShortcutBackend.win32RegisterHotKey,
      available: true,
      applicationChoosesChord: true,
      userMayRebind: false,
      needsSystemPermission: false,
      unavailableBecause: null,
    ),
    ShortcutHost.macos => const ShortcutSupport(
      backend: ShortcutBackend.carbonEventHotKey,
      available: true,
      applicationChoosesChord: true,
      userMayRebind: false,
      needsSystemPermission: false,
      unavailableBecause: null,
    ),
    ShortcutHost.linux => _linux(),
    ShortcutHost.other => const ShortcutSupport(
      backend: ShortcutBackend.none,
      available: false,
      applicationChoosesChord: false,
      userMayRebind: false,
      needsSystemPermission: false,
      unavailableBecause:
          'this platform has no system-wide shortcut surface this channel '
          'speaks to',
    ),
  };

  ShortcutSupport _linux() {
    final String declared =
        environment['XDG_SESSION_TYPE']?.trim().toLowerCase() ?? '';
    final bool waylandSocket = (environment['WAYLAND_DISPLAY'] ?? '')
        .trim()
        .isNotEmpty;
    final bool x11Display = (environment['DISPLAY'] ?? '').trim().isNotEmpty;

    final bool wayland =
        declared != 'x11' && (declared == 'wayland' || waylandSocket);
    final bool x11 = !wayland && (declared == 'x11' || x11Display);

    if (x11) {
      return ShortcutSupport(
        backend: ShortcutBackend.x11GrabKey,
        available: true,
        applicationChoosesChord: true,
        userMayRebind: false,
        needsSystemPermission: false,
        unavailableBecause: null,
        sessionName: desktopName,
      );
    }

    if (wayland) {
      return ShortcutSupport(
        backend: ShortcutBackend.waylandPortal,
        available: false,
        applicationChoosesChord: false,
        userMayRebind: true,
        needsSystemPermission: true,
        sessionName: desktopName,
        unavailableBecause:
            'a Wayland session grants a system-wide shortcut only through '
            'the desktop portal, where the compositor owns the chord and the '
            'user confirms it. This channel does not speak that portal yet, '
            'and it reports that instead of registering a shortcut that '
            'never fires. The session is ${desktopName ?? 'unnamed'}.',
      );
    }

    return const ShortcutSupport(
      backend: ShortcutBackend.none,
      available: false,
      applicationChoosesChord: false,
      userMayRebind: false,
      needsSystemPermission: false,
      unavailableBecause:
          'neither a Wayland socket nor an X display is reachable from this '
          'process, so there is no session to bind a shortcut in',
    );
  }

  /// `XDG_CURRENT_DESKTOP`, when set.
  String? get desktopName {
    final String raw = (environment['XDG_CURRENT_DESKTOP'] ?? '').trim();
    return raw.isEmpty ? null : raw;
  }
}
