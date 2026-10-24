@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:dovetail_cli/src/doctor/rust_target_probe.dart';
import 'package:dovetail_cli/src/doctor/tool_probe.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

void main() {
  late Directory root;
  late String tools;
  final String cli = p.join(repoRoot(), 'toolkit', 'dovetail_cli');

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_rust_target');
    tools = p.join(root.path, 'Rust Tools');
    Directory(tools).createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  Map<String, dynamic> namedProbe({int exitCode = 0}) {
    File(p.join(tools, 'test-rustup')).writeAsStringSync('#!/bin/sh\nexit 0\n');
    File(p.join(tools, 'test-rustup.cmd')).writeAsStringSync(
      '@echo off\r\n'
      'if not "%~1"=="target" exit /b 41\r\n'
      'if not "%~2"=="list" exit /b 42\r\n'
      'if not "%~3"=="--installed" exit /b 43\r\n'
      'echo x86_64-unknown-linux-gnu\r\n'
      'echo aarch64-pc-windows-msvc\r\n'
      'echo wrapper refused >&2\r\nexit /b $exitCode\r\n',
    );
    final File driver = File(p.join(root.path, 'probe.dart'))
      ..writeAsStringSync('''
import 'dart:convert';
import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:dovetail_cli/src/doctor/rust_target_probe.dart';
Future<void> main() async {
  final report = await RustTargetProbe(os: TargetOs.windows,
    arch: TargetArch.arm64, rustup: 'test-rustup').probe();
  print(jsonEncode({'status': report.status.name, 'detail': report.detail}));
}
''');
    final ProcessResult result = Process.runSync(
      Platform.resolvedExecutable,
      <String>[
        '--packages=${p.join(cli, '.dart_tool', 'package_config.json')}',
        driver.path,
      ],
      environment: <String, String>{
        'PATH': '$tools;${Platform.environment['SystemRoot']}\\System32',
      },
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    return jsonDecode(result.stdout as String) as Map<String, dynamic>;
  }

  test(
    'RustTargetProbe runs a named Windows wrapper and asks for installed targets',
    () {
      expect(namedProbe()['status'], 'usable');
    },
  );

  test(
    'a named Windows rustup wrapper failure is broken rather than absent',
    () {
      final Map<String, dynamic> report = namedProbe(exitCode: 7);
      expect(report['status'], 'unusable');
      expect(report['detail'], contains('wrapper refused'));
    },
  );

  test(
    'an existing invalid rustup executable is broken rather than absent',
    () async {
      final File invalid = File(p.join(tools, 'broken rustup.exe'))
        ..writeAsStringSync('not a PE executable');
      final ToolReport report = await RustTargetProbe(
        os: TargetOs.windows,
        arch: TargetArch.arm64,
        rustup: invalid.path,
      ).probe();
      expect(report.status, ToolStatus.unusable);
      expect(report.detail, isNotEmpty);
    },
  );
}
