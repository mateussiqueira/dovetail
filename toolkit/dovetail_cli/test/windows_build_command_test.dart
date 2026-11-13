@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

void main() {
  late Directory root;
  late Directory tools;
  final String cli = p.join(repoRoot(), 'toolkit', 'dovetail_cli');

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_windows_build');
    tools = Directory(p.join(root.path, 'Flutter SDK'))..createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  ProcessResult build({List<String> extra = const <String>[]}) {
    return Process.runSync(
      Platform.resolvedExecutable,
      <String>[
        '--packages=${p.join(cli, '.dart_tool', 'package_config.json')}',
        p.join(cli, 'bin', 'dovetail.dart'),
        'build',
        '--root',
        root.path,
        ...extra,
      ],
      environment: <String, String>{
        'PATH': '${tools.path};${Platform.environment['SystemRoot']}\\System32',
        'DOVETAIL_TEST_ARGS': p.join(root.path, 'args.json'),
      },
    );
  }

  void batch(int code) {
    File(
      p.join(tools.path, 'flutter'),
    ).writeAsStringSync('#!/bin/sh\nexit 99\n');
    File(p.join(tools.path, 'flutter.bat')).writeAsStringSync(
      '@echo off\r\necho %* > "${p.join(root.path, 'args.txt')}"\r\nexit /b $code\r\n',
    );
  }

  test('build starts the default Flutter batch entry from a Windows PATH', () {
    batch(0);
    final ProcessResult result = build();
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(
      File(p.join(root.path, 'args.txt')).readAsStringSync().trim(),
      'build windows --release',
    );
    expect(result.stdout, contains('output'));
  });

  test('build propagates the default Flutter batch failure exit code', () {
    batch(23);
    final ProcessResult result = build();
    expect(result.exitCode, 23, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, isNot(contains('output   ')));
  });

  test('an explicit native Flutter executable retains literal arguments', () {
    final File source = File(p.join(root.path, 'recorder.dart'))
      ..writeAsStringSync(
        "import 'dart:convert'; import 'dart:io'; "
        'void main(List<String> args) {'
        "File(Platform.environment['DOVETAIL_TEST_ARGS']!).writeAsStringSync(jsonEncode(args));}",
      );
    final String executable = p.join(tools.path, 'native flutter.exe');
    final ProcessResult compiled = Process.runSync(
      Platform.resolvedExecutable,
      <String>['compile', 'exe', source.path, '-o', executable],
    );
    expect(
      compiled.exitCode,
      0,
      reason: '${compiled.stdout}\n${compiled.stderr}',
    );
    const List<String> values = <String>[
      'space value',
      'quoted "value"',
      'a&b|c>d<e^f%g!h',
      'ação',
      '',
    ];
    final ProcessResult result = build(
      extra: <String>[
        '--flutter',
        executable,
        for (final String value in values) '--flutter-arg=$value',
      ],
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(
      jsonDecode(File(p.join(root.path, 'args.json')).readAsStringSync()),
      <String>['build', 'windows', '--release', ...values],
    );
  });
}
