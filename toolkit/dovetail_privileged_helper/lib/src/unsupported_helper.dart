import 'package:dovetail_privileged_helper/src/approval_pane.dart';
import 'package:dovetail_privileged_helper/src/helper_backend.dart';
import 'package:dovetail_privileged_helper/src/helper_state.dart';
import 'package:dovetail_privileged_helper/src/helper_status.dart';
import 'package:dovetail_privileged_helper/src/privileged_helper.dart';

/// A helper for a host with no privileged-helper flow this package speaks.
///
/// Answers [HelperState.unsupported] to everything, carrying the sentence that
/// says why, and it is what the selector returns for a phone, for a browser,
/// for macOS before 13, and for the Network Extension route that is declared
/// but not implemented.
///
/// It exists so that no caller needs a null check and no caller needs a
/// platform branch. The alternative — a nullable helper — moves the decision
/// back into every screen, which is where it was in the product this package
/// came from, and where it was got wrong.
final class UnsupportedHelper implements PrivilegedHelper {
  /// A helper that refuses everything, saying [because].
  const UnsupportedHelper(
    this.because, {
    this.approvalPane = ApprovalPane.noPaneOffDesktop,
  });

  /// The sentence attached to every answer.
  final String because;

  @override
  final ApprovalPane approvalPane;

  @override
  HelperBackend get backend => HelperBackend.none;

  @override
  Future<HelperStatus> status() async => _answer;

  @override
  Future<HelperStatus> register() async => _answer;

  @override
  Future<HelperStatus> unregister() async => _answer;

  @override
  Future<ApprovalPaneOutcome> openApprovalSettings() async =>
      ApprovalPaneOutcome.absent;

  HelperStatus get _answer => HelperStatus(
    state: HelperState.unsupported,
    backend: HelperBackend.none,
    detail: because,
  );
}
