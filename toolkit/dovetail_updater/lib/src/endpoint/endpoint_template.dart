import 'package:dovetail_updater/src/update_failure.dart';

final class EndpointTemplate {
  const EndpointTemplate(this.template);

  final String template;

  String resolve({
    required String currentVersion,
    required String target,
    required String arch,
    required String bundleType,
  }) {
    final String resolved = template
        .replaceAll('{{current_version}}', Uri.encodeComponent(currentVersion))
        .replaceAll('{{target}}', target)
        .replaceAll('{{arch}}', arch)
        .replaceAll('{{bundle_type}}', bundleType);

    if (resolved.contains('{{')) {
      throw UpdateFailure(
        'the endpoint still has an unresolved placeholder: $resolved',
        remedy:
            'Only current_version, target, arch and bundle_type are '
            'substituted.',
      );
    }

    final Uri uri = Uri.parse(resolved);
    if (uri.scheme != 'https') {
      throw UpdateFailure(
        'the update endpoint is not https: $resolved',
        remedy:
            'The manifest itself is not signed, so its integrity rests '
            'entirely on the transport. Plain http would let anyone point the '
            'client at a different artefact.',
      );
    }

    return resolved;
  }
}
