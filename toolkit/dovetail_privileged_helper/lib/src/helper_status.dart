import 'package:dovetail_privileged_helper/src/helper_backend.dart';
import 'package:dovetail_privileged_helper/src/helper_state.dart';

/// One answer from the platform: the state, who reported it, and why.
///
/// Every call on `PrivilegedHelper` returns one of these, including the calls
/// that refuse. A refusal that came back as `false` would be a call whose
/// result the UI has to guess at; a refusal that comes back as the current
/// state with a sentence attached is one the UI can render.
final class HelperStatus {
  /// A status as some backend reported it.
  const HelperStatus({required this.state, required this.backend, this.detail});

  /// Where the privileged component stands.
  final HelperState state;

  /// The facility that answered, or [HelperBackend.none] when none did.
  final HelperBackend backend;

  /// One sentence saying what happened, ready to show, or null when the state
  /// says everything.
  ///
  /// Present on every refusal and every failure. This is where the difference
  /// between "the property list is not in the bundle" and "an administrator
  /// disabled the service" lives, and both of those arrive as states a user
  /// cannot act on — so the sentence is the whole of what can be shown.
  final String? detail;

  /// Whether the privileged component is installed and permitted to run.
  bool get isEnabled => state.isEnabled;

  /// Whether calling `register` can move this state. See [HelperState.mayRegister].
  bool get mayRegister => state.mayRegister;

  /// Whether the user has to act outside the app before this can be enabled.
  bool get needsApproval => state.needsApproval;

  /// Whether any sequence of calls could ever reach [HelperState.enabled] here.
  bool get canEverBeEnabled => state.canEverBeEnabled;

  /// The same status with [detail] replaced.
  ///
  /// For a caller that has more context about a state than the backend did —
  /// a refusal, mostly, where the reason belongs to the decision and not to
  /// the platform that reported the state.
  HelperStatus because(String detail) =>
      HelperStatus(state: state, backend: backend, detail: detail);

  @override
  bool operator ==(Object other) =>
      other is HelperStatus &&
      other.state == state &&
      other.backend == backend &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(state, backend, detail);

  @override
  String toString() =>
      'HelperStatus(${state.name}, ${backend.name}'
      '${detail == null ? '' : ', $detail'})';
}
