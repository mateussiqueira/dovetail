@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

void main() {
  late Directory binaries;
  late Directory root;
  late String first;
  late String second;
  late String project;
  late String sdk;
  final String cli = p.join(repoRoot(), 'toolkit', 'dovetail_cli');

  String compile(String name, String source) {
    final File file = File(p.join(binaries.path, '$name.dart'))
      ..writeAsStringSync(source);
    final String output = p.join(binaries.path, '$name.exe');
    final ProcessResult result =
        Process.runSync(Platform.resolvedExecutable, <String>[
          'compile',
          'exe',
          '--packages=${p.join(cli, '.dart_tool', 'package_config.json')}',
          file.path,
          '-o',
          output,
        ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    return output;
  }

  setUpAll(() {
    binaries = Directory.systemTemp.createTempSync('dovetail_upgrade_binaries');
    compile('upgrade', '''
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:dovetail_cli/src/command/upgrade_command.dart';
import 'package:dovetail_cli/src/sdk/sdk_locator.dart';
Future<void> main(List<String> args) async {
  final runner = CommandRunner<int>('dovetail', 'test')
    ..addCommand(UpgradeCommand(sdkLocator: SdkLocator(home: args[0])));
  exitCode = await runner.run(['upgrade', '--root', args[1], '--check']) ?? 0;
}
''');
    compile('native', '''
import 'dart:convert';
import 'dart:io';
void main(List<String> args) {
  File('native-entry.json').writeAsStringSync(jsonEncode(args));
  exit(int.parse(Platform.environment['DART_FIXTURE_EXIT']!));
}
''');
  });

  tearDownAll(() => binaries.deleteSync(recursive: true));

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_upgrade_launcher');
    first = p.join(root.path, 'First Dart');
    second = p.join(root.path, 'Second Dart');
    project = p.join(root.path, 'Project');
    sdk = p.join(root.path, 'SDK Home');
    for (final String directory in <String>[first, second, project]) {
      Directory(directory).createSync();
    }
    File(p.join(project, 'pubspec.yaml')).writeAsStringSync('name: demo\n');
    final Directory package = Directory(
      p.join(sdk, 'sdk', '0.2.0', 'packages', 'dovetail'),
    )..createSync(recursive: true);
    File(
      p.join(package.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: dovetail\nversion: 0.2.0\n');
    File(
      p.join(binaries.path, 'native.exe'),
    ).copySync(p.join(second, 'dart.exe'));
  });

  tearDown(() => root.deleteSync(recursive: true));

  void batch(int code) {
    File(p.join(first, 'dart.cmd')).writeAsStringSync(
      '@echo off\r\n'
      'if not "%~1"=="pub" exit /b 41\r\n'
      'if not "%~2"=="get" exit /b 42\r\n'
      'echo selected > batch-entry.txt\r\n'
      'echo batch pub refused >&2\r\nexit /b $code\r\n',
    );
  }

  ProcessResult upgrade({required int nativeExit}) => Process.runSync(
    p.join(binaries.path, 'upgrade.exe'),
    <String>[sdk, project],
    environment: <String, String>{
      'PATH': '$first;$second;${Platform.environment['SystemRoot']}\\System32',
      'DART_FIXTURE_EXIT': '$nativeExit',
    },
  );

  test('upgrade check selects an earlier Windows Dart batch launcher', () {
    batch(0);
    final ProcessResult result = upgrade(nativeExit: 29);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(File(p.join(project, 'batch-entry.txt')).existsSync(), isTrue);
    expect(File(p.join(project, 'native-entry.json')).existsSync(), isFalse);
  });

  test(
    'upgrade check refuses the first Dart launcher failure without falling back',
    () {
      batch(11);
      final ProcessResult result = upgrade(nativeExit: 0);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('batch pub refused'));
      expect(File(p.join(project, 'native-entry.json')).existsSync(), isFalse);
    },
  );

  test(
    'upgrade check still accepts a native Dart executable without a batch launcher',
    () {
      final ProcessResult result = upgrade(nativeExit: 0);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        jsonDecode(
          File(p.join(project, 'native-entry.json')).readAsStringSync(),
        ),
        <String>['pub', 'get'],
      );
    },
  );
}
