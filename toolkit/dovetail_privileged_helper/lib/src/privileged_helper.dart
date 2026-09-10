import 'package:dovetail_privileged_helper/src/approval_pane.dart';
import 'package:dovetail_privileged_helper/src/helper_backend.dart';
import 'package:dovetail_privileged_helper/src/helper_status.dart';

/// The privileged component of one app, as this host reports it.
///
/// A desktop application that has to do something a sandboxed GUI process
/// cannot — bind a privileged port, configure a network interface, talk to
/// a driver — carries a second, privileged process. Putting it in place is an operating-system
/// permission flow with several outcomes, not a file copy, and this is the
/// interface over that flow.
///
/// Four calls, and every one of them answers with a state. None returns a
/// bool, including the ones that refuse: a refusal is a state the screen has
/// to render, and `false` is not renderable.
///
/// Implementations never throw for a platform answer. A host with no such
/// flow, an administrator who forbade it, a property list missing from the
/// bundle — all of those are states, and a screen that has to wrap every
/// status read in a try/catch ends up rendering the catch.
abstract interface class PrivilegedHelper {
  /// The facility behind this helper, or [HelperBackend.none].
  HelperBackend get backend;

  /// Where the user grants what the app cannot grant itself, on this host.
  ///
  /// Read it before drawing anything: `ApprovalPane.exists` being false is
  /// what tells a screen not to offer a button that leads nowhere.
  ApprovalPane get approvalPane;

  /// Asks the platform where the component stands, right now.
  ///
  /// Cheap enough to call on every window focus, and that is the intended
  /// use: the approval happens *outside* the app, so an app that reads this
  /// once at launch shows "not approved" to a person who approved it a minute
  /// ago and came back. `HelperWatch` wires that up.
  Future<HelperStatus> status();

  /// Puts the component in place, if this state allows it.
  ///
  /// Reads [status] first and refuses anything but
  /// `HelperState.notRegistered`, returning that state with a sentence saying
  /// why. The refusal that matters is `requiresApproval`: registering an
  /// already-registered daemon reports success on macOS and changes nothing,
  /// so a "repair" button wired straight through would spin forever without
  /// ever being wrong enough to notice.
  ///
  /// Success is not [HelperState.enabled]. On macOS the daemon registers into
  /// `requiresApproval` and stays there until a human acts, so the returned
  /// status is the one to render, not a signal to move on.
  Future<HelperStatus> register();

  /// Takes the component out, if it is in.
  ///
  /// Refuses when there is nothing registered, for the same reason [register]
  /// refuses when there already is.
  Future<HelperStatus> unregister();

  /// Brings up the settings pane where the user approves the component.
  ///
  /// Answers with an outcome and not a bool because "it did not open" covers
  /// both a platform that has no such pane and a pane that refused to come
  /// up, and those are different things to say to somebody.
  ///
  /// Opening the pane never changes [status]. The user acts in another
  /// application, at their own pace, and possibly not at all — reading the
  /// status again, when the window comes back, is the only way to learn what
  /// they did.
  Future<ApprovalPaneOutcome> openApprovalSettings();
}
