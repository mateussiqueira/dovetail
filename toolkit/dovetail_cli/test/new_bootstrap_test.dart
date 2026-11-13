import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:dovetail_cli/src/sdk/sdk_locator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support/repo_root.dart';

void main() {
  late Directory root;
  final String runtime = p.join(repoRoot(), 'toolkit', 'dovetail_rust_core');

  setUp(() => root = Directory.systemTemp.createTempSync('dovetail_bootstrap'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<String> scaffold() async {
    final CommandRunner<int> runner = CommandRunner<int>('dovetail', 'test')
      ..addCommand(
        NewCommand(sdkLocator: SdkLocator(home: p.join(root.path, 'no_sdk'))),
      );
    expect(
      await runner.run(<String>[
        'new',
        '--root',
        root.path,
        '--name',
        'bootstrap',
        '--dovetail-path',
        p.join(repoRoot(), 'toolkit', 'dovetail'),
        '--no-create',
      ]),
      0,
    );
    return p.join(root.path, 'bootstrap');
  }

  test(
    'new pins the bridge runtime at the app root before pub resolution',
    () async {
      final String app = await scaffold();
      final File overrides = File(p.join(app, 'pubspec_overrides.yaml'));
      expect(overrides.existsSync(), isTrue);
      final YamlMap source = loadYaml(overrides.readAsStringSync()) as YamlMap;
      final YamlMap packages = source['dependency_overrides'] as YamlMap;
      expect((packages['dovetail_rust_core'] as YamlMap)['path'], runtime);
    },
  );

  test(
    'new resolves its first pub get without handwritten overrides',
    () async {
      if (Process.runSync(Platform.isWindows ? 'where' : 'which', <String>[
            'flutter',
          ]).exitCode !=
          0) {
        markTestSkipped('Flutter is not installed');
        return;
      }
      final String app = await scaffold();
      final ProcessResult result = Process.runSync(
        'flutter',
        <String>['pub', 'get'],
        workingDirectory: app,
        runInShell: Platform.isWindows,
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final File config = File(
        p.join(app, '.dart_tool', 'package_config.json'),
      );
      final Map<String, dynamic> packages =
          jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
      final Map<String, dynamic> core = (packages['packages'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .singleWhere(
            (Map<String, dynamic> item) => item['name'] == 'dovetail_rust_core',
          );
      final String resolved = config.uri
          .resolve(core['rootUri'] as String)
          .toFilePath();
      expect(
        Directory(resolved).resolveSymbolicLinksSync(),
        Directory(runtime).resolveSymbolicLinksSync(),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
