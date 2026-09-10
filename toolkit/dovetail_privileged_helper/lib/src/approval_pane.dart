import 'package:dovetail_privileged_helper/src/helper_host.dart';

/// What happened when the approval pane was asked to open.
///
/// Three values and not a bool, for the same reason the state enum has six:
/// "it did not open" is two different situations. [absent] is a platform that
/// has no such pane at all, which the app should have been told before it drew
/// a button; [failed] is a pane that exists and did not come up, which is
/// worth reporting.
enum ApprovalPaneOutcome {
  /// The system was asked to bring the pane forward.
  ///
  /// Note what this does not claim: not that the window is visible, not that
  /// the user saw it, and certainly not that anything was approved. The
  /// answer to "did they approve it?" only ever comes from reading the status
  /// again.
  opened,

  /// This platform has no settings pane for this permission.
  absent,

  /// The pane exists and the system refused to open it.
  failed,
}

/// The settings pane where a user grants what the app cannot grant itself.
///
/// Without one, `HelperState.requiresApproval` is a dead end: the app can say
/// "approve it" and the person has nowhere to go. With one, the app can put
/// them in front of the switch.
///
/// The URL lives here, in Dart, rather than inside the native code, and that
/// is a deliberate structural choice: a second macOS backend approves in a
/// *different* pane — a Network Extension approves under Network, not under
/// Login Items — and if the destination were compiled into the Objective-C,
/// adding
/// that backend would mean writing native code to open a different window.
final class ApprovalPane {
  const ApprovalPane._({this.uri, this.absentBecause});

  /// The pane for [host], or one that reports why there is none.
  factory ApprovalPane.of(HelperHost host) => switch (host) {
    HelperHost.macos => ApprovalPane.macOSLoginItems,
    HelperHost.windows => ApprovalPane.noWindowsPane,
    HelperHost.linux => ApprovalPane.noLinuxPane,
    HelperHost.other => ApprovalPane.noPaneOffDesktop,
  };

  /// System Settings › General › Login Items, where macOS 13+ shows a
  /// registered daemon waiting to be switched on.
  ///
  /// `SMAppService` also ships `openSystemSettingsLoginItems()`, which opens
  /// exactly this and is the supported call. It is the fallback here rather
  /// than the primary, because it can only ever open *that* pane — see the
  /// note on this class about the second backend. The native side tries this
  /// URL first and falls back to Apple's call if the system refuses it, so a
  /// pane identifier that rots in a future release degrades to the wrong-but-
  /// working window instead of to nothing.
  static const ApprovalPane macOSLoginItems = ApprovalPane._(uri: _loginItems);

  /// Windows has no Settings page for services.
  static const ApprovalPane noWindowsPane = ApprovalPane._(
    absentBecause:
        'Windows has no Settings page for services. Installing one is an '
        'elevation prompt that either succeeds or does not, so there is no '
        'pending state to send anybody to; a service an administrator has '
        'disabled is re-enabled in services.msc, which is a console and not '
        'a pane, and only by an administrator.',
  );

  /// Linux desktops do not agree on a target, so none is guessed.
  static const ApprovalPane noLinuxPane = ApprovalPane._(
    absentBecause:
        'no Linux desktop exposes a settings pane for systemd units, and the '
        'desktops do not agree on a settings surface at all. There is no '
        'portal for it either. Opening the wrong window is worse than saying '
        'there is none, so this says there is none.',
  );

  /// Off the desktop there is no privileged component to approve.
  static const ApprovalPane noPaneOffDesktop = ApprovalPane._(
    absentBecause:
        'this platform has no privileged helper to approve, so there is no '
        'pane for one',
  );

  /// Undocumented by Apple, and stable across Ventura, Sonoma and Sequoia.
  /// The fallback in the native code exists because "undocumented" is exactly
  /// the kind of thing that changes in a point release.
  static const String _loginItems =
      'x-apple.systempreferences:com.apple.LoginItems-Settings.extension';

  /// The pane to open, or null when this host has none.
  final String? uri;

  /// When there is no pane, the sentence that says why — ready to show.
  final String? absentBecause;

  /// Whether there is a pane to open at all.
  bool get exists => uri != null;

  @override
  bool operator ==(Object other) =>
      other is ApprovalPane &&
      other.uri == uri &&
      other.absentBecause == absentBecause;

  @override
  int get hashCode => Object.hash(uri, absentBecause);

  @override
  String toString() => 'ApprovalPane(${uri ?? 'none: $absentBecause'})';
}
