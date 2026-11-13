@TestOn('windows')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

void main() {
  late Directory root;
  late Map<String, String> environment;
  final String cli = p.join(repoRoot(), 'toolkit', 'dovetail_cli');
  final String packages = p.join(cli, '.dart_tool', 'package_config.json');

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_windows_lookup');
    environment = <String, String>{
      'PATH': '${root.path};${Platform.environment['SystemRoot']}\\System32',
    };
  });

  tearDown(() => root.deleteSync(recursive: true));

  ProcessResult probeCodegen() {
    final File driver = File(p.join(root.path, 'probe.dart'));
    final Uri bridge = File(
      p.join(cli, 'lib', 'src', 'dev', 'frb_bridge.dart'),
    ).uri;
    driver.writeAsStringSync(
      "import '$bridge';\n"
      'void main() {\n'
      "  final bridge = FrbBridge.parse('rust_root: rust\\ndart_output: lib', "
      "origin: 'bridge.yaml');\n"
      '  print(bridge.codegenAvailable);\n'
      '}\n',
    );
    return Process.runSync(Platform.resolvedExecutable, <String>[
      '--packages=$packages',
      driver.path,
    ], environment: environment);
  }

  test('dev finds codegen on Windows without Unix tools on PATH', () {
    File(
      p.join(root.path, 'flutter_rust_bridge_codegen.cmd'),
    ).writeAsStringSync('@exit /b 0\r\n');
    final ProcessResult result = probeCodegen();
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout.toString().trim(), 'true');
  });

  test('dev reports missing codegen without throwing on Windows', () {
    final ProcessResult result = probeCodegen();
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout.toString().trim(), 'false');
  });

  test('new fills platform folders using Flutter on Windows', () {
    File(
      p.join(root.path, 'flutter.cmd'),
    ).writeAsStringSync('@echo off\r\nmkdir windows\r\nexit /b 0\r\n');
    final ProcessResult result =
        Process.runSync(Platform.resolvedExecutable, <String>[
          '--packages=$packages',
          p.join(cli, 'bin', 'dovetail.dart'),
          'new',
          '--root',
          root.path,
          '--name',
          'windows_lookup',
          '--dovetail-path',
          p.join(repoRoot(), 'toolkit', 'dovetail'),
        ], environment: environment);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(
      Directory(p.join(root.path, 'windows_lookup', 'windows')).existsSync(),
      isTrue,
    );
  });
}
