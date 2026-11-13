import 'package:yaml/yaml.dart';

Map<String, String> sdkOverridePaths(String source) {
  final YamlMap overrides =
      (loadYaml(source) as YamlMap)['dependency_overrides'] as YamlMap;
  return <String, String>{
    for (final Object? name in overrides.keys)
      name as String: (overrides[name] as YamlMap)['path'] as String,
  };
}
