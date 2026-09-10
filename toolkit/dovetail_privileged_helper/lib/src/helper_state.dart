/// Where the privileged component stands with the operating system.
///
/// Six values, and the reason there are six rather than two is that a bool
/// collapses journeys with nothing in common. The product this package was
/// extracted from exposed `helperIsInstalled()` as a bool and drew one button
/// — "Repair service" — for three situations: one where installing is the
/// move, one where installing is a no-op and the person has to approve the
/// daemon in System Settings, and one where an administrator has forbidden it
/// and no amount of pressing will ever help. Two thirds of the people who saw
/// that button were being asked to do something that could not work.
///
/// The names are not invented here. On macOS 13 and later,
/// `SMAppService.daemon(plistName:)` reports `notRegistered`, `enabled`,
/// `requiresApproval` and `notFound`, and this enum is that shape plus the two
/// answers the other platforms need.
enum HelperState {
  /// This platform has no privileged-helper flow this package speaks.
  ///
  /// Not a failure and not a refusal by the user: there is nothing to install
  /// and nobody to ask. A phone, a browser, and macOS before 13 — where the
  /// route was `SMJobBless`, a different flow with no approval state, and
  /// deliberately not implemented here.
  unsupported,

  /// The component is not installed, and installing it is the move on offer.
  ///
  /// The only state in which `register` can change anything.
  notRegistered,

  /// Installed, and waiting for the user to approve it outside the app.
  ///
  /// The state that makes this enum worth having. macOS 13 registers the
  /// daemon and then shows it, switched off, in System Settings › General ›
  /// Login Items. Registering again returns success and changes nothing — the
  /// approval is not the app's to grant. The only honest move is to open that
  /// pane and say what to look for.
  requiresApproval,

  /// Installed and permitted to run.
  enabled,

  /// Forbidden by something above the user: MDM, group policy, a masked unit.
  ///
  /// Separate from [requiresApproval] because it is not a choice anybody in
  /// front of this screen can make. Telling someone to "allow it in Settings"
  /// when their employer has forbidden it sends them to a switch that is not
  /// there, and is worse than saying nothing.
  blockedByPolicy,

  /// The platform was asked and answered with an error.
  ///
  /// Distinct from [notRegistered]: a property list missing from the app
  /// bundle reports here, and no number of installs fixes a build. The
  /// sentence in `HelperStatus.detail` is what says which.
  failed;

  /// Whether the privileged component is installed and permitted to run.
  bool get isEnabled => this == HelperState.enabled;

  /// Whether calling `register` can move this state.
  ///
  /// True for [notRegistered] alone. The exclusion that matters is
  /// [requiresApproval]: a second `register` on a daemon awaiting approval
  /// succeeds and changes nothing, so a button wired to it looks broken and
  /// gets pressed again. A UI that reads this instead of "is it installed?"
  /// cannot draw that button.
  bool get mayRegister => this == HelperState.notRegistered;

  /// Whether the user has to act outside the app before this can be [enabled].
  bool get needsApproval => this == HelperState.requiresApproval;

  /// Whether any sequence of calls could ever reach [enabled] on this host.
  ///
  /// False for [unsupported] and [blockedByPolicy] — the two states where the
  /// answer does not depend on anything the app or the person at the keyboard
  /// does. A screen that offers a retry here is promising something it cannot
  /// deliver.
  bool get canEverBeEnabled =>
      this != HelperState.unsupported && this != HelperState.blockedByPolicy;
}
