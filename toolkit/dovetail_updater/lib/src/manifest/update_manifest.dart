import 'package:dovetail_updater/src/manifest/platform_release.dart';
import 'package:dovetail_updater/src/update_failure.dart';
import 'package:pub_semver/pub_semver.dart';

final class UpdateManifest {
  const UpdateManifest({
    required this.version,
    required this.releases,
    this.notes,
    this.publishedAt,
  });

  final Version version;
  final Map<String, PlatformRelease> releases;
  final String? notes;
  final DateTime? publishedAt;

  static const String universalSuffix = '-universal';

  PlatformRelease releaseFor(String platformKey) {
    final PlatformRelease? exact = releases[platformKey];
    if (exact != null) {
      return exact;
    }

    final String universal = '${platformKey.split('-').first}$universalSuffix';
    final PlatformRelease? fat = releases[universal];
    if (fat != null) {
      return fat;
    }

    throw UpdateFailure(
      'the manifest for $version has nothing for $platformKey.',
      remedy:
          'It offers ${releases.keys.join(', ')}. A publisher may ship one '
          'artefact per architecture or one universal artefact under '
          '$universal, and a client asks for its own architecture first.',
    );
  }
}
