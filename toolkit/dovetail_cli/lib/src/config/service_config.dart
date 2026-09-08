import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:dovetail_cli/src/config/config_failure.dart';

final class ServiceConfig {
  const ServiceConfig({
    required this.unit,
    required this.policy,
    required this.scripts,
  });

  factory ServiceConfig.fromMap(
    Map<String, Object?> map,
    String origin, {
    required String identifier,
  }) {
    final SystemdUnit unit = _unitOf(map, origin);
    return ServiceConfig(
      unit: unit,
      policy: _policyOf(map, origin, identifier: identifier),
      scripts: ServiceScripts(
        unitFileName: unit.fileName,
        purgePaths: _stringList(
          map['purge-paths'],
          'service.purge-paths',
          origin,
        ),
      ),
    );
  }

  final SystemdUnit unit;
  final PolkitPolicy? policy;
  final ServiceScripts scripts;

  static SystemdUnit _unitOf(Map<String, Object?> map, String origin) {
    final String name = _required(map, 'name', origin);
    if (!name.endsWith('.service')) {
      throw ConfigFailure(
        'service.name is "$name".',
        remedy:
            'systemd loads a unit by its file name, so it has to end in '
            '.service or nothing installs.',
        origin: origin,
      );
    }

    try {
      return SystemdUnit(
        fileName: name,
        description: _required(map, 'description', origin),
        execStart: _required(map, 'exec-start', origin),
        capabilityBoundingSet: _capabilities(map, origin),
        ambientCapabilities: _capabilities(map, origin),
        runtimeDirectory: _directory(map, 'runtime-directory', origin),
        stateDirectory: _directory(map, 'state-directory', origin),
        logsDirectory: _directory(map, 'logs-directory', origin),
      );
    } on BundleFailure catch (failure) {
      throw ConfigFailure(
        failure.message,
        remedy: failure.remedy,
        origin: origin,
      );
    }
  }

  static SystemdDirectory? _directory(
    Map<String, Object?> map,
    String key,
    String origin,
  ) {
    final Object? value = map[key];
    if (value == null) {
      return null;
    }
    if (value is String) {
      return SystemdDirectory(name: value, mode: '0750');
    }
    if (value is Map<String, Object?>) {
      return SystemdDirectory(
        name: _required(value, 'name', origin),
        mode: value['mode'] as String? ?? '0750',
      );
    }
    throw ConfigFailure(
      'service.$key must be a directory name, or a name and a mode.',
      remedy:
          'systemd reads these as relative to /run, /var/lib and /var/log, so '
          'an absolute path here is a directory nothing creates.',
      origin: origin,
    );
  }

  static Set<String> _capabilities(Map<String, Object?> map, String origin) =>
      _stringList(map['capabilities'], 'service.capabilities', origin).toSet();

  static PolkitPolicy? _policyOf(
    Map<String, Object?> map,
    String origin, {
    required String identifier,
  }) {
    final Object? section = map['polkit'];
    if (section == null) {
      return null;
    }
    if (section is! Map<String, Object?>) {
      throw ConfigFailure('service.polkit must be a mapping.', origin: origin);
    }

    final String action = _required(section, 'action', origin);
    if (!action.startsWith('$identifier.')) {
      throw ConfigFailure(
        'the polkit action "$action" is outside the "$identifier" namespace.',
        remedy:
            'polkit names the file after the namespace and refuses an action '
            'declared outside it, so the rule would install and never apply.',
        origin: origin,
      );
    }

    try {
      return PolkitPolicy(
        namespace: identifier,
        vendor: _required(section, 'vendor', origin),
        actions: <PolkitAction>[
          PolkitAction(
            id: action,
            description: _required(section, 'description', origin),
            message: _required(section, 'message', origin),
          ),
        ],
      );
    } on BundleFailure catch (failure) {
      throw ConfigFailure(
        failure.message,
        remedy: failure.remedy,
        origin: origin,
      );
    }
  }

  static String _required(Map<String, Object?> map, String key, String origin) {
    final Object? value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw ConfigFailure('service.$key is missing.', origin: origin);
    }
    return value;
  }

  static List<String> _stringList(Object? value, String field, String origin) {
    if (value == null) {
      return const <String>[];
    }
    if (value is! List) {
      throw ConfigFailure('$field must be a list.', origin: origin);
    }
    return <String>[
      for (final Object? entry in value)
        if (entry is String)
          entry
        else
          throw ConfigFailure(
            '$field holds a non-string entry.',
            origin: origin,
          ),
    ];
  }
}
