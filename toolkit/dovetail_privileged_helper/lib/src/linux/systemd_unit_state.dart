import 'package:dovetail_privileged_helper/src/helper_backend.dart';
import 'package:dovetail_privileged_helper/src/helper_state.dart';
import 'package:dovetail_privileged_helper/src/helper_status.dart';

/// Translates a word from `systemctl is-enabled` into a [HelperStatus].
///
/// systemd has a dozen of these words and they do not group the way a first
/// reading suggests. Two of them matter more than the rest:
///
/// `disabled` means the unit file is installed and switched off, which is
/// something the app can offer to change. `not-found` means there is no unit
/// file at all, which the app can do nothing about — on Linux the unit is
/// installed by the distribution package, never by the running application.
/// Folding both into "not installed" would put an enable button in front of
/// somebody whose package is simply missing, and it would never work.
///
/// The exit code is not the signal, and this is the trap worth naming:
/// `systemctl is-enabled` exits non-zero for `disabled` as well as for
/// `not-found`, so a caller that reads the code instead of the word cannot
/// tell a healthy switched-off unit from a missing one.
abstract final class SystemdUnitState {
  /// The state for one word, and the diagnostic to attach when there is none.
  ///
  /// [word] is the first line of standard output, trimmed. An empty or
  /// unrecognised word reads as [HelperState.failed] carrying [diagnostic],
  /// which is systemd's own sentence: an older `systemctl` prints nothing for
  /// a unit it cannot find and explains itself on standard error, in the
  /// user's language, and matching a translated sentence to guess "not
  /// installed" would be a guess dressed as a reading.
  static HelperStatus fromWord(
    String word, {
    required String unitName,
    String? diagnostic,
  }) => switch (word.trim()) {
    // `static` has no [Install] section, so it can never be enabled and is
    // pulled in by something else. For the question this package asks — may
    // the privileged component run — that is a yes.
    'enabled' ||
    'enabled-runtime' ||
    'static' ||
    'indirect' ||
    'generated' ||
    'transient' ||
    'alias' ||
    'linked' ||
    'linked-runtime' => const HelperStatus(
      state: HelperState.enabled,
      backend: HelperBackend.systemdUnit,
    ),
    'disabled' => const HelperStatus(
      state: HelperState.notRegistered,
      backend: HelperBackend.systemdUnit,
    ),
    'masked' || 'masked-runtime' => HelperStatus(
      state: HelperState.blockedByPolicy,
      backend: HelperBackend.systemdUnit,
      detail:
          '$unitName is masked, which is an administrator linking it to '
          '/dev/null so that nothing can start it. Enabling it from here '
          'fails every time until they unmask it.',
    ),
    'not-found' => HelperStatus(
      state: HelperState.failed,
      backend: HelperBackend.systemdUnit,
      detail:
          'systemd knows no unit named $unitName. The unit file comes from '
          'the package that installed this application, not from the '
          'application, so there is nothing here to enable — the install is '
          'incomplete.',
    ),
    _ => HelperStatus(
      state: HelperState.failed,
      backend: HelperBackend.systemdUnit,
      detail: diagnostic == null
          ? 'systemctl answered "$word" for $unitName, which this version of '
                'the package does not know'
          : 'systemctl did not name a state for $unitName. It said: '
                '$diagnostic',
    ),
  };
}
