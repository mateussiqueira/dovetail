import 'package:dovetail_privileged_helper/src/helper_backend.dart';
import 'package:dovetail_privileged_helper/src/helper_state.dart';
import 'package:dovetail_privileged_helper/src/helper_status.dart';

/// Translates what `SMAppService` reported into a [HelperStatus].
///
/// The four numbers are Apple's, declared in `SMAppService.Status`, and this
/// class exists so the translation is a pure function a `flutter test` can
/// exercise on any machine — the Objective-C beside it cannot be, and neither
/// can a real daemon.
///
/// One state never comes out of here, and that is worth knowing before
/// reading a screen built on it: macOS 13 has no status for "an administrator
/// forbade this". A configuration profile that denies login items leaves the
/// status at [HelperState.notRegistered] and makes the registration fail, so
/// [HelperState.blockedByPolicy] on this platform would be a guess. It is not
/// guessed; the registration error is reported as a failure with Apple's own
/// sentence in it.
abstract final class DarwinServiceStatus {
  /// `SMAppServiceStatusNotRegistered`.
  static const int notRegistered = 0;

  /// `SMAppServiceStatusEnabled`.
  static const int enabled = 1;

  /// `SMAppServiceStatusRequiresApproval`.
  static const int requiresApproval = 2;

  /// `SMAppServiceStatusNotFound`: no such property list in this bundle.
  static const int notFound = 3;

  /// The state for one of Apple's four numbers.
  ///
  /// An unknown number reads as [HelperState.failed] rather than as
  /// [HelperState.notRegistered]. A macOS newer than this package could add a
  /// fifth, and offering to install something whose real state is unread is
  /// how a screen ends up lying with confidence.
  static HelperStatus fromRaw(int raw, {required String plistName}) =>
      switch (raw) {
        DarwinServiceStatus.notRegistered => const HelperStatus(
          state: HelperState.notRegistered,
          backend: HelperBackend.launchDaemon,
        ),
        DarwinServiceStatus.enabled => const HelperStatus(
          state: HelperState.enabled,
          backend: HelperBackend.launchDaemon,
        ),
        DarwinServiceStatus.requiresApproval => const HelperStatus(
          state: HelperState.requiresApproval,
          backend: HelperBackend.launchDaemon,
          detail:
              'macOS has registered the daemon and is holding it switched '
              'off until somebody turns it on in System Settings › General › '
              'Login Items. Registering it again reports success and changes '
              'nothing.',
        ),
        DarwinServiceStatus.notFound => HelperStatus(
          state: HelperState.failed,
          backend: HelperBackend.launchDaemon,
          detail:
              'macOS found no $plistName in this app bundle. That is a '
              'packaging fault, not a missing install: the property list has '
              'to be built into Contents/Library/LaunchDaemons, and no number '
              'of registrations puts it there.',
        ),
        _ => HelperStatus(
          state: HelperState.failed,
          backend: HelperBackend.launchDaemon,
          detail:
              'macOS reported service status $raw, which this version of the '
              'package does not know. Reading it as "not installed" would '
              'offer an install for a state nobody here has read.',
        ),
      };

  /// The status inside one reply from the method channel.
  ///
  /// The native side answers with a map carrying at most one of three keys —
  /// `raw` for a status it read, `unsupported` for a macOS with no
  /// `SMAppService`, `error` for a call that threw — and this is the whole of
  /// the wire contract, kept in one place so the Objective-C and the Dart
  /// cannot drift apart quietly.
  ///
  /// `error` alongside `raw` is the case that matters: a registration can
  /// fail and the status still be readable, and then the state is the one the
  /// platform reports while the sentence is the one the platform threw.
  /// Reporting the failure alone would lose that a daemon is already there.
  static HelperStatus fromReply(Object? reply, {required String plistName}) {
    if (reply is! Map<Object?, Object?>) {
      return HelperStatus(
        state: HelperState.failed,
        backend: HelperBackend.launchDaemon,
        detail:
            'the macOS side answered ${reply.runtimeType} where a map was '
            'expected, so nothing about the daemon is known',
      );
    }

    final Object? unsupported = reply['unsupported'];
    if (unsupported is String) {
      return HelperStatus(
        state: HelperState.unsupported,
        backend: HelperBackend.none,
        detail: unsupported,
      );
    }

    final Object? raw = reply['raw'];
    final Object? error = reply['error'];
    if (raw is int) {
      final HelperStatus read = fromRaw(raw, plistName: plistName);
      return error is String ? read.because(error) : read;
    }

    return HelperStatus(
      state: HelperState.failed,
      backend: HelperBackend.launchDaemon,
      detail: error is String
          ? error
          : 'the macOS side answered without a status and without a reason',
    );
  }
}
