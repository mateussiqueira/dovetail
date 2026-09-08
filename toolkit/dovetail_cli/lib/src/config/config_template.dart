import 'package:dovetail_cli/src/config/project_probe.dart';

final class ConfigTemplate {
  const ConfigTemplate._();

  static String render(ProjectProbe probe, {String? identifier}) {
    final List<String> targets = probe.targets;
    final String resolved =
        identifier ??
        probe.declaredIdentifier ??
        ProjectProbe.sanitized('com.example.${probe.packageName ?? 'app'}');

    final StringBuffer out = StringBuffer()
      ..writeln('# Written by: dovetail init')
      ..writeln('# The version is read from pubspec.yaml, never repeated here.')
      ..writeln()
      ..writeln('identifier: $resolved')
      ..writeln('name: ${probe.suggestedName}')
      ..writeln('manufacturer: ${probe.suggestedName}')
      ..writeln()
      ..writeln('# One platform key per artefact this product ships.')
      ..writeln('# A key no client asks for is a release nobody can see.')
      ..writeln('targets:');

    for (final String target in targets) {
      out.writeln('  - $target');
    }

    out
      ..writeln()
      ..writeln('update:')
      ..writeln('  key: keys/update.key')
      ..writeln('  password-env: DOVETAIL_UPDATE_KEY_PASSWORD')
      ..writeln('  # Uncomment and point at your own host: dovetail ship')
      ..writeln('  # refuses without it, because the url is the one part of')
      ..writeln('  # the manifest it cannot derive from the project. The url')
      ..writeln('  # is built as <base-url>/<version>/<file>.')
      ..writeln('  # base-url: https://cdn.example.com/releases')
      ..writeln('  manifest: dist/latest.json')
      ..writeln('  # Paste the public-key line that `dovetail keygen` prints:')
      ..writeln('  # doctor says `missing update` and ship refuses without it.')
      ..writeln('  # public-key: <base64 from dovetail keygen>')
      ..writeln()
      ..writeln('# Identities are never written here, only the variables')
      ..writeln('# that carry them, so this file is safe to commit.')
      ..writeln('sign:')
      ..writeln('  macos:')
      ..writeln('    identity-env: DOVETAIL_MACOS_IDENTITY');

    final String? icon = probe.iconPath;
    if (icon != null) {
      out.writeln('    # entitlements: macos/Runner/Release.entitlements');
    }

    out
      ..writeln('    notarize: false')
      ..writeln('  windows:')
      ..writeln('    certificate-env: DOVETAIL_WINDOWS_CERTIFICATE')
      ..writeln('    timestamp-url: http://timestamp.digicert.com');

    if (icon != null) {
      out
        ..writeln()
        ..writeln('# Detected: $icon')
        ..writeln('#   dovetail icon --source $icon');
    }

    return out.toString();
  }
}
