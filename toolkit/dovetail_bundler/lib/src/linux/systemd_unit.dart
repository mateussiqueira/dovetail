import 'package:dovetail_bundler/src/bundle_failure.dart';

enum SystemdServiceType {
  exec('exec'),
  simple('simple'),
  notify('notify'),
  forking('forking');

  const SystemdServiceType(this.wireName);

  final String wireName;
}

final class SystemdDirectory {
  const SystemdDirectory({required this.name, required this.mode});

  final String name;
  final String mode;
}

final class SystemdUnit {
  SystemdUnit({
    required this.fileName,
    required this.description,
    required this.execStart,
    this.documentation,
    this.after = const <String>['network.target'],
    this.execStopPost,
    this.type = SystemdServiceType.exec,
    this.restart = 'on-failure',
    this.restartSeconds = 2,
    this.timeoutStopSeconds = 20,
    this.runtimeDirectory,
    this.logsDirectory,
    this.stateDirectory,
    this.capabilityBoundingSet = const <String>{},
    this.ambientCapabilities = const <String>{},
    this.protectSystem = 'full',
    this.restrictAddressFamilies = const <String>{},
    this.wantedBy = const <String>['multi-user.target'],
    this.extraHardening = const <String, String>{},
  }) {
    if (!fileName.endsWith('.service')) {
      throw BundleFailure(
        'the unit file is named "$fileName".',
        remedy:
            'systemd decides what a unit is from its extension. Name it '
            '<something>.service.',
      );
    }
    if (execStart.trim().isEmpty || !execStart.trim().startsWith('/')) {
      throw BundleFailure(
        'ExecStart is "$execStart", which is not an absolute path.',
        remedy:
            'systemd resolves nothing on PATH for a system unit. Give the '
            'installed location of the executable.',
      );
    }
    if (wantedBy.isEmpty) {
      throw const BundleFailure(
        'the unit declares no WantedBy, so it has no [Install] section.',
        remedy:
            'systemctl enable creates no symlink for a unit with no install '
            'target. The package would install a service that never starts '
            'at boot, and nothing would report an error.',
      );
    }

    final Set<String> escaping = ambientCapabilities.difference(
      capabilityBoundingSet,
    );
    if (escaping.isNotEmpty) {
      throw BundleFailure(
        'ambient capabilities ${escaping.join(', ')} are not in the bounding '
        'set.',
        remedy:
            'systemd drops an ambient capability that the bounding set does '
            'not carry, and it does so silently: the service starts, and the '
            'privileged call fails at the moment a user needs it.',
      );
    }

    for (final SystemdDirectory? directory in <SystemdDirectory?>[
      runtimeDirectory,
      logsDirectory,
      stateDirectory,
    ]) {
      if (directory != null && directory.name.startsWith('/')) {
        throw BundleFailure(
          'the directory "${directory.name}" is absolute.',
          remedy:
              'RuntimeDirectory, LogsDirectory and StateDirectory are named '
              'relative to /run, /var/log and /var/lib. systemd refuses an '
              'absolute value.',
        );
      }
    }
  }

  final String fileName;
  final String description;
  final String execStart;
  final String? documentation;
  final List<String> after;
  final String? execStopPost;
  final SystemdServiceType type;
  final String restart;
  final int restartSeconds;
  final int timeoutStopSeconds;
  final SystemdDirectory? runtimeDirectory;
  final SystemdDirectory? logsDirectory;
  final SystemdDirectory? stateDirectory;
  final Set<String> capabilityBoundingSet;
  final Set<String> ambientCapabilities;
  final String protectSystem;
  final Set<String> restrictAddressFamilies;
  final List<String> wantedBy;
  final Map<String, String> extraHardening;

  static const String installedUnitDirectory = '/usr/lib/systemd/system';

  String get installedPath => '$installedUnitDirectory/$fileName';

  String render() {
    final StringBuffer out = StringBuffer()
      ..writeln('[Unit]')
      ..writeln('Description=$description');
    if (documentation != null && documentation!.trim().isNotEmpty) {
      out.writeln('Documentation=$documentation');
    }
    if (after.isNotEmpty) {
      out.writeln('After=${after.join(' ')}');
    }

    out
      ..writeln()
      ..writeln('[Service]')
      ..writeln('Type=${type.wireName}')
      ..writeln('ExecStart=$execStart');
    if (execStopPost != null && execStopPost!.trim().isNotEmpty) {
      out.writeln('ExecStopPost=$execStopPost');
    }
    out
      ..writeln('Restart=$restart')
      ..writeln('RestartSec=${restartSeconds}s')
      ..writeln('TimeoutStopSec=${timeoutStopSeconds}s');

    _writeDirectory(out, 'RuntimeDirectory', runtimeDirectory);
    _writeDirectory(out, 'LogsDirectory', logsDirectory);
    _writeDirectory(out, 'StateDirectory', stateDirectory);

    if (capabilityBoundingSet.isNotEmpty) {
      out.writeln(
        'CapabilityBoundingSet=${_sorted(capabilityBoundingSet).join(' ')}',
      );
    }
    if (ambientCapabilities.isNotEmpty) {
      out.writeln(
        'AmbientCapabilities=${_sorted(ambientCapabilities).join(' ')}',
      );
    }
    out
      ..writeln('NoNewPrivileges=yes')
      ..writeln('ProtectSystem=$protectSystem')
      ..writeln('ProtectHome=yes')
      ..writeln('PrivateTmp=yes')
      ..writeln('ProtectClock=yes')
      ..writeln('ProtectHostname=yes')
      ..writeln('ProtectControlGroups=yes')
      ..writeln('RestrictNamespaces=yes')
      ..writeln('RestrictRealtime=yes')
      ..writeln('RestrictSUIDSGID=yes')
      ..writeln('LockPersonality=yes')
      ..writeln('MemoryDenyWriteExecute=yes')
      ..writeln('SystemCallArchitectures=native')
      ..writeln('RemoveIPC=yes')
      ..writeln('UMask=0077');

    if (restrictAddressFamilies.isNotEmpty) {
      out.writeln(
        'RestrictAddressFamilies='
        '${_sorted(restrictAddressFamilies).join(' ')}',
      );
    }
    for (final String key in _sorted(extraHardening.keys.toSet())) {
      out.writeln('$key=${extraHardening[key]}');
    }

    out
      ..writeln()
      ..writeln('[Install]')
      ..writeln('WantedBy=${wantedBy.join(' ')}');

    return out.toString();
  }

  void _writeDirectory(
    StringBuffer out,
    String key,
    SystemdDirectory? directory,
  ) {
    if (directory == null) {
      return;
    }
    out
      ..writeln('$key=${directory.name}')
      ..writeln('${key}Mode=${directory.mode}');
  }

  static List<String> _sorted(Set<String> values) =>
      values.toList(growable: false)..sort();
}
