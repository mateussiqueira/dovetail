import 'package:dovetail_bundler/src/bundle_failure.dart';

final class ServiceScripts {
  ServiceScripts({
    required this.unitFileName,
    this.purgePaths = const <String>[],
    this.refreshDesktopDatabase = true,
  }) {
    if (!unitFileName.endsWith('.service')) {
      throw BundleFailure(
        'the unit named in the maintainer scripts is "$unitFileName".',
        remedy: 'It has to be the same file the package installs.',
      );
    }
    for (final String path in purgePaths) {
      if (!path.startsWith('/')) {
        throw BundleFailure(
          'the purge path "$path" is not absolute.',
          remedy:
              'These paths are removed by rm -rf during purge. A relative one '
              'would delete whatever sits under the maintainer script\'s '
              'working directory.',
        );
      }
      if (path.contains(' ')) {
        throw BundleFailure(
          'the purge path "$path" contains a space.',
          remedy:
              'The purge loop splits on whitespace, so a path with a space '
              'would be removed as two wrong paths.',
        );
      }
      if (path.split('/').where((String s) => s.isNotEmpty).length < 2) {
        throw BundleFailure(
          'the purge path "$path" is too close to the root.',
          remedy: 'rm -rf on a top-level directory is not a purge.',
        );
      }
    }
  }

  final String unitFileName;
  final List<String> purgePaths;
  final bool refreshDesktopDatabase;

  String get debianPostinst => <String>[
    '#!/bin/sh',
    'set -e',
    '',
    'if [ "\$1" = "configure" ] || [ "\$1" = "abort-upgrade" ] || '
        '[ "\$1" = "abort-deconfigure" ] || [ "\$1" = "abort-remove" ]; then',
    "\tdeb-systemd-helper unmask '$unitFileName' >/dev/null || true",
    '',
    "\tif deb-systemd-helper --quiet was-enabled '$unitFileName'; then",
    "\t\tdeb-systemd-helper enable '$unitFileName' >/dev/null || true",
    '\telse',
    "\t\tdeb-systemd-helper update-state '$unitFileName' >/dev/null || true",
    '\tfi',
    '',
    '\tif [ -d /run/systemd/system ]; then',
    '\t\tsystemctl --system daemon-reload >/dev/null || true',
    '\t\tif [ -n "\$2" ]; then',
    '\t\t\t_action=restart',
    '\t\telse',
    '\t\t\t_action=start',
    '\t\tfi',
    "\t\tdeb-systemd-invoke \$_action '$unitFileName' >/dev/null || true",
    '\tfi',
    'fi',
    if (refreshDesktopDatabase) ...<String>[
      '',
      'if [ "\$1" = "configure" ] && '
          'command -v update-desktop-database >/dev/null 2>&1; then',
      '\tupdate-desktop-database -q /usr/share/applications || true',
      'fi',
    ],
    '',
    'exit 0',
    '',
  ].join('\n');

  String get debianPrerm => <String>[
    '#!/bin/sh',
    'set -e',
    '',
    'if [ -z "\$DPKG_ROOT" ] && [ "\$1" = remove ] && '
        '[ -d /run/systemd/system ]; then',
    "\tdeb-systemd-invoke stop '$unitFileName' >/dev/null || true",
    'fi',
    '',
    'exit 0',
    '',
  ].join('\n');

  String get debianPostrm => <String>[
    '#!/bin/sh',
    'set -e',
    '',
    'if [ "\$1" = "purge" ]; then',
    "\tdeb-systemd-helper purge '$unitFileName' >/dev/null || true",
    'fi',
    '',
    'if [ "\$1" = remove ] && [ -d /run/systemd/system ]; then',
    '\tsystemctl --system daemon-reload >/dev/null || true',
    'fi',
    if (purgePaths.isNotEmpty) ...<String>[
      '',
      "_purge_paths='${purgePaths.join(' ')}'",
      'if [ "\$1" = "purge" ] && [ -n "\$_purge_paths" ]; then',
      '\tfor _p in \$_purge_paths; do',
      '\t\trm -rf "\$_p"',
      '\tdone',
      'fi',
    ],
    if (refreshDesktopDatabase) ...<String>[
      '',
      'if [ "\$1" = remove ] || [ "\$1" = purge ]; then',
      '\tif command -v update-desktop-database >/dev/null 2>&1; then',
      '\t\tupdate-desktop-database -q /usr/share/applications || true',
      '\tfi',
      'fi',
    ],
    '',
    'exit 0',
    '',
  ].join('\n');

  String get rpmPost => <String>[
    '%systemd_post $unitFileName',
    if (refreshDesktopDatabase)
      'command -v update-desktop-database >/dev/null 2>&1 && '
          'update-desktop-database -q /usr/share/applications || :',
  ].join('\n');

  String get rpmPreun => '%systemd_preun $unitFileName';

  String get rpmPostun => <String>[
    '%systemd_postun_with_restart $unitFileName',
    if (refreshDesktopDatabase)
      'command -v update-desktop-database >/dev/null 2>&1 && '
          'update-desktop-database -q /usr/share/applications || :',
  ].join('\n');

  static const int scriptMode = 0x1ED;
}
