import 'package:dovetail_updater/src/manifest/update_manifest.dart';
import 'package:dovetail_updater/src/policy/downgrade_refused.dart';
import 'package:dovetail_updater/src/policy/update_decision.dart';
import 'package:pub_semver/pub_semver.dart';

final class UpdatePolicy {
  const UpdatePolicy({this.allowDowngrade = false});

  final bool allowDowngrade;

  UpdateDecision decide({
    required Version installed,
    required UpdateManifest manifest,
  }) {
    final Version offered = manifest.version;

    if (offered == installed) {
      return const UpdateDecision.upToDate(
        'the offered version is the installed one',
      );
    }

    if (offered < installed) {
      if (!allowDowngrade) {
        throw DowngradeRefused(offered: offered, installed: installed);
      }
      return UpdateDecision.available(offered);
    }

    return UpdateDecision.available(offered);
  }
}
