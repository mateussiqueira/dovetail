import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

void main() {
  late Directory root;
  late String profile;
  late File driver;
  final String cli = p.join(repoRoot(), 'toolkit', 'dovetail_cli');

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_sdk_home');
    profile = p.join(root.path, 'Windows User');
    Directory(
      p.join(profile, '.dovetail', 'sdk', '0.1.0', 'packages'),
    ).createSync(recursive: true);
    final Uri locator = File(p.join(cli, 'lib/src/sdk/sdk_locator.dart')).uri;
    final Uri installer = File(
      p.join(cli, 'lib/src/sdk/sdk_installer.dart'),
    ).uri;
    driver = File(p.join(root.path, 'probe.dart'))
      ..writeAsStringSync(
        "import 'dart:convert';\nimport '$locator';\nimport '$installer';\n"
        'void main(List<String> args) {\n'
        '  final locator = SdkLocator(home: args.isEmpty ? null : args[0]);\n'
        '  final installer = SdkInstaller(home: locator.home, '
        'binDir: args.length < 2 ? null : args[1]);\n'
        "  print(jsonEncode({'home': locator.home, 'bin': installer.binDir, "
        "'version': locator.locate()?.version}));\n}\n",
      );
  });

  tearDown(() => root.deleteSync(recursive: true));

  Map<String, dynamic> probe({
    Map<String, String> extra = const <String, String>{},
    List<String> arguments = const <String>[],
    String? cwd,
  }) {
    final Map<String, String> env = Map<String, String>.of(
      Platform.environment,
    );
    for (final String name in <String>[
      'HOME',
      'LOCALAPPDATA',
      'USERPROFILE',
      'DOVETAIL_HOME',
      'DOVETAIL_BIN_DIR',
    ]) {
      env.remove(name);
    }
    env.addAll(<String, String>{'USERPROFILE': profile, ...extra});
    final ProcessResult result = Process.runSync(
      Platform.resolvedExecutable,
      <String>[
        '--packages=${p.join(cli, '.dart_tool', 'package_config.json')}',
        driver.path,
        ...arguments,
      ],
      environment: env,
      includeParentEnvironment: false,
      workingDirectory: cwd,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
  }

  test(
    'without HOME the SDK follows USERPROFILE across working directories',
    () {
      for (final String name in <String>['project one', 'project two']) {
        final Directory cwd = Directory(p.join(root.path, name))..createSync();
        final Map<String, dynamic> result = probe(cwd: cwd.path);
        expect(result['home'], p.join(profile, '.dovetail'));
        expect(result['version'], '0.1.0');
      }
    },
  );

  test('without HOME the CLI bin directory stays under USERPROFILE', () {
    expect(probe()['bin'], p.join(profile, '.local', 'bin'));
  });

  test(
    'Windows SDK home follows LOCALAPPDATA instead of the shell HOME',
    () {
      final String local = p.join(root.path, 'Local App Data');
      final Map<String, dynamic> result = probe(
        extra: <String, String>{
          'HOME': p.join(root.path, 'Shell Home'),
          'LOCALAPPDATA': local,
        },
      );
      expect(result['home'], p.join(local, 'dovetail'));
    },
    skip: !Platform.isWindows,
  );

  test('HOME keeps precedence over USERPROFILE', () {
    final String home = p.join(root.path, 'Unix Home');
    final Map<String, dynamic> result = probe(
      extra: <String, String>{'HOME': home},
    );
    expect(result['home'], p.join(home, '.dovetail'));
    expect(result['bin'], p.join(home, '.local', 'bin'));
  });

  test('DOVETAIL_HOME overrides the SDK without moving the user bin', () {
    final String sdk = p.join(root.path, 'custom SDK');
    final Map<String, dynamic> result = probe(
      extra: <String, String>{'DOVETAIL_HOME': sdk},
    );
    expect(result['home'], sdk);
    expect(result['bin'], p.join(profile, '.local', 'bin'));
  });

  test('explicit SDK and bin paths win over environment overrides', () {
    final String sdk = p.join(root.path, 'explicit SDK');
    final String bin = p.join(root.path, 'explicit bin');
    final Map<String, dynamic> result = probe(
      extra: <String, String>{
        'DOVETAIL_HOME': 'other SDK',
        'DOVETAIL_BIN_DIR': 'other bin',
      },
      arguments: <String>[sdk, bin],
    );
    expect(result['home'], sdk);
    expect(result['bin'], bin);
  });

  test('DOVETAIL_BIN_DIR still overrides the default bin directory', () {
    final String bin = p.join(root.path, 'custom bin');
    expect(probe(extra: <String, String>{'DOVETAIL_BIN_DIR': bin})['bin'], bin);
  });
}
