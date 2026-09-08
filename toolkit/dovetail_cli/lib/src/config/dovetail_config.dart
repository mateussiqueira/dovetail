import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:dovetail_cli/src/config/config_failure.dart';
import 'package:dovetail_cli/src/config/macos_signing_config.dart';
import 'package:dovetail_cli/src/config/service_config.dart';
import 'package:dovetail_cli/src/config/update_config.dart';
import 'package:dovetail_cli/src/config/windows_signing_config.dart';
import 'package:yaml/yaml.dart';

final class DovetailConfig {
  const DovetailConfig({
    required this.identifier,
    required this.name,
    required this.manufacturer,
    required this.targets,
    required this.update,
    required this.macos,
    required this.windows,
    required this.service,
  });

  factory DovetailConfig.parse(
    String source, {
    String origin = 'dovetail.yaml',
  }) {
    final Object? document = _documentOf(source, origin);
    if (document is! Map) {
      throw ConfigFailure(
        'the file does not hold a mapping.',
        remedy: 'Write it as "identifier: ...", one key per line.',
        origin: origin,
      );
    }

    final Map<String, Object?> map = _asMap(document);

    final String identifier = _identifierOf(map, origin);
    return DovetailConfig(
      identifier: identifier,
      name: _nameOf(map, origin),
      manufacturer: _manufacturerOf(map, origin),
      targets: _targetsOf(map, origin),
      update: map['update'] == null
          ? null
          : UpdateConfig.fromMap(_section(map, 'update', origin), origin),
      macos: _signSection(map, 'macos', origin) == null
          ? null
          : MacosSigningConfig.fromMap(
              _signSection(map, 'macos', origin)!,
              origin,
            ),
      windows: _signSection(map, 'windows', origin) == null
          ? null
          : WindowsSigningConfig.fromMap(
              _signSection(map, 'windows', origin)!,
              origin,
            ),
      service: map['service'] == null
          ? null
          : ServiceConfig.fromMap(
              _section(map, 'service', origin),
              origin,
              identifier: identifier,
            ),
    );
  }

  final String identifier;
  final String name;
  final String manufacturer;
  final List<String> targets;
  final UpdateConfig? update;
  final MacosSigningConfig? macos;
  final WindowsSigningConfig? windows;
  final ServiceConfig? service;

  Iterable<String> targetsForOs(String os) =>
      targets.where((String target) => target.startsWith('$os-'));

  static Object? _documentOf(String source, String origin) {
    try {
      return loadYaml(source);
    } on YamlException catch (error) {
      throw ConfigFailure(
        'the file is not valid yaml.',
        remedy: error.message,
        origin: origin,
      );
    }
  }

  static Map<String, Object?> _asMap(Map<Object?, Object?> raw) =>
      <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in raw.entries)
          '${entry.key}': entry.value is Map
              ? _asMap(entry.value! as Map<Object?, Object?>)
              : entry.value is List
              ? (entry.value! as List<Object?>).toList()
              : entry.value,
      };

  static Map<String, Object?> _section(
    Map<String, Object?> map,
    String key,
    String origin,
  ) {
    final Object? value = map[key];
    if (value is! Map<String, Object?>) {
      throw ConfigFailure('$key must be a mapping.', origin: origin);
    }
    return value;
  }

  static Map<String, Object?>? _signSection(
    Map<String, Object?> map,
    String os,
    String origin,
  ) {
    if (map['sign'] == null) {
      return null;
    }
    final Map<String, Object?> sign = _section(map, 'sign', origin);
    if (sign[os] == null) {
      return null;
    }
    return _section(sign, os, origin);
  }

  static String _identifierOf(Map<String, Object?> map, String origin) {
    final Object? value = map['identifier'];
    if (value is! String || value.isEmpty) {
      throw ConfigFailure(
        'identifier is missing.',
        remedy:
            'It is the reverse-dns name the bundle, the single-instance guard '
            'and the deep-link scheme all key off, so it cannot be guessed.',
        origin: origin,
      );
    }
    if (!_identifierPattern.hasMatch(value)) {
      throw ConfigFailure(
        '"$value" is not a reverse-dns identifier.',
        remedy:
            'Write it as com.example.app: letters, digits and hyphens, at '
            'least two segments. macOS refuses a bundle id outside that shape.',
        origin: origin,
      );
    }
    return value;
  }

  static String _nameOf(Map<String, Object?> map, String origin) {
    final Object? value = map['name'];
    if (value is! String || value.trim().isEmpty) {
      throw ConfigFailure(
        'name is missing.',
        remedy: 'It is what the user reads in the window title and the tray.',
        origin: origin,
      );
    }
    return value;
  }

  static String _manufacturerOf(Map<String, Object?> map, String origin) {
    final Object? value = map['manufacturer'];
    if (value is! String || value.trim().isEmpty) {
      throw ConfigFailure(
        'manufacturer is missing.',
        remedy:
            'Every installer format carries it: the MSI writes it into the '
            'product table, Add or Remove Programs shows it, and a .deb names '
            'it as the maintainer. There is no sensible default.',
        origin: origin,
      );
    }
    return value;
  }

  static List<String> _targetsOf(Map<String, Object?> map, String origin) {
    final Object? value = map['targets'];
    if (value is! List || value.isEmpty) {
      throw ConfigFailure(
        'targets is missing or empty.',
        remedy:
            'List the platform keys this product ships, for example '
            'darwin-aarch64. A release with no declared target is a release '
            'no client can ask for.',
        origin: origin,
      );
    }

    final List<String> targets = <String>[];
    for (final Object? entry in value) {
      if (entry is! String) {
        throw ConfigFailure(
          'targets holds a non-string entry.',
          origin: origin,
        );
      }
      try {
        PlatformKey.validate(entry);
      } on UpdateFailure catch (failure) {
        throw ConfigFailure(
          'targets: ${failure.message}',
          remedy: failure.remedy,
          origin: origin,
        );
      }
      if (targets.contains(entry)) {
        throw ConfigFailure('targets names "$entry" twice.', origin: origin);
      }
      targets.add(entry);
    }
    return targets;
  }

  static final RegExp _identifierPattern = RegExp(
    r'^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$',
  );
}
