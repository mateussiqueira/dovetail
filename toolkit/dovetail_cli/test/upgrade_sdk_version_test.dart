import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_cli/src/command/upgrade_command.dart';
import 'package:dovetail_cli/src/sdk/sdk_locator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support/stdout_capture.dart';

void main() {
  late Directory root;
  late Directory sdk;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_upgrade_version');
    sdk = Directory(p.join(root.path, 'SDK Home'))..createSync();
    final Directory package = Directory(
      p.join(sdk.path, 'sdk', '0.2.0', 'packages', 'dovetail'),
    )..createSync(recursive: true);
    File(
      p.join(package.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: dovetail\nversion: 0.2.0\n');
    File(
      p.join(root.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: demo\nversion: 0.1.0\n');
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<String> upgrade(String? path) async {
    if (path != null) {
      File(p.join(root.path, 'pubspec_overrides.yaml')).writeAsStringSync(
        'dependency_overrides:\n  dovetail:\n    path: $path\n',
      );
    }
    final CommandRunner<int> runner = CommandRunner<int>('dovetail', 'test')
      ..addCommand(UpgradeCommand(sdkLocator: SdkLocator(home: sdk.path)));
    final CapturedStdout captured = CapturedStdout();
    final int? code = await capturingStdout(
      captured,
      () => runner.run(<String>['upgrade', '--root', root.path]),
    );
    expect(code, 0);
    final YamlMap overrides =
        loadYaml(
              File(
                p.join(root.path, 'pubspec_overrides.yaml'),
              ).readAsStringSync(),
            )
            as YamlMap;
    expect(
      overrides['dependency_overrides']['dovetail']['path'],
      p.join(sdk.path, 'sdk', '0.2.0', 'packages', 'dovetail'),
    );
    return captured.text.toString();
  }

  const String windows =
      r'C:\Users\Dart User\.dovetail\sdk\0.0.9\packages\dovetail';
  final Map<String, String> paths = <String, String>{
    'POSIX': '/opt/dovetail/sdk/0.0.9/packages/dovetail',
    'Windows plain': windows,
    'Windows YAML quoted': jsonEncode(windows),
    'Windows mixed separators': r'C:\Dart User/sdk\0.0.9/packages\dovetail',
    'Windows UNC': jsonEncode(r'\\server\share\sdk\0.0.9\packages\dovetail'),
  };
  for (final MapEntry<String, String> entry in paths.entries) {
    test(
      'upgrade reports the SDK version transition for ${entry.key}',
      () async {
        expect(await upgrade(entry.value), contains('0.0.9 → 0.2.0'));
      },
    );
  }

  test(
    'an unchanged SDK version does not claim a version transition',
    () async {
      expect(
        await upgrade(jsonEncode(windows.replaceFirst('0.0.9', '0.2.0'))),
        isNot(contains('→')),
      );
    },
  );

  test('a first SDK override does not invent a previous version', () async {
    expect(await upgrade(null), isNot(contains('→')));
  });
}
