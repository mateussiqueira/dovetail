import 'package:dovetail_privileged_helper/src/approval_pane.dart';
import 'package:dovetail_privileged_helper/src/darwin/darwin_service_status.dart';
import 'package:dovetail_privileged_helper/src/helper_backend.dart';
import 'package:dovetail_privileged_helper/src/helper_state.dart';
import 'package:dovetail_privileged_helper/src/helper_status.dart';
import 'package:dovetail_privileged_helper/src/privileged_helper.dart';
import 'package:dovetail_privileged_helper/src/registration_guard.dart';
import 'package:flutter/services.dart';

/// The macOS 13+ route: a root daemon registered with `SMAppService`.
///
/// A method channel and not FFI, which is the opposite of the choice the
/// single-instance guard next door makes. The reason is the shape of the API,
/// not taste: `SMAppService` is an Objective-C class with an `NSError`
/// out-parameter, an availability guard, and a class method that opens a
/// window. Flattening all of that into a C ABI would mean inventing an error
/// encoding, and the errors are the part worth keeping — Apple's sentence
/// about why a registration failed is better than anything this package would
/// write in its place.
final class DarwinDaemonHelper implements PrivilegedHelper {
  /// A helper over the daemon declared by [plistName] in this app bundle.
  const DarwinDaemonHelper({required this.plistName, MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// The channel the Objective-C side answers on.
  ///
  /// Public because the native code and the tests both have to spell it, and
  /// a string spelled in three places is a string that goes wrong in one.
  static const String channelName = 'dovetail_privileged_helper';

  /// The property list under `Contents/Library/LaunchDaemons`, with its
  /// extension.
  final String plistName;

  final MethodChannel _channel;

  @override
  HelperBackend get backend => HelperBackend.launchDaemon;

  @override
  ApprovalPane get approvalPane => ApprovalPane.macOSLoginItems;

  @override
  Future<HelperStatus> status() => _ask('status');

  @override
  Future<HelperStatus> register() async {
    final HelperStatus current = await status();
    return RegistrationGuard.refuseRegister(current) ?? await _ask('register');
  }

  @override
  Future<HelperStatus> unregister() async {
    final HelperStatus current = await status();
    return RegistrationGuard.refuseUnregister(current) ??
        await _ask('unregister');
  }

  @override
  Future<ApprovalPaneOutcome> openApprovalSettings() async {
    final String? uri = approvalPane.uri;
    if (uri == null) {
      return ApprovalPaneOutcome.absent;
    }
    try {
      final Object? reply = await _channel.invokeMethod<Object?>(
        'openApprovalSettings',
        <String, Object?>{'uri': uri},
      );
      final bool opened =
          reply is Map<Object?, Object?> && reply['opened'] == true;
      return opened ? ApprovalPaneOutcome.opened : ApprovalPaneOutcome.failed;
    } on PlatformException {
      return ApprovalPaneOutcome.failed;
    } on MissingPluginException {
      return ApprovalPaneOutcome.failed;
    }
  }

  Future<HelperStatus> _ask(String method) async {
    try {
      final Object? reply = await _channel.invokeMethod<Object?>(
        method,
        <String, Object?>{'plist': plistName},
      );
      return DarwinServiceStatus.fromReply(reply, plistName: plistName);
    } on PlatformException catch (error) {
      return HelperStatus(
        state: HelperState.failed,
        backend: HelperBackend.launchDaemon,
        detail:
            'the macOS side raised ${error.code}: '
            '${error.message ?? 'no message'}',
      );
    } on MissingPluginException {
      // Not a platform limit, and worth separating from one: the plugin is
      // simply not in this binary. That is a widget test, or an application
      // built before this package was added to it — and answering
      // `unsupported` there would tell a Mac that macOS cannot do this.
      return const HelperStatus(
        state: HelperState.failed,
        backend: HelperBackend.launchDaemon,
        detail:
            'the dovetail_privileged_helper plugin is not registered in this '
            'process, so macOS was never asked. In a widget test that is '
            'expected; in a built app it means the plugin did not make it '
            'into the runner.',
      );
    }
  }
}
