@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

void main() {
  late Directory root;
  late String first;
  late String second;
  late File driver;
  final String cli = p.join(repoRoot(), 'toolkit', 'dovetail_cli');

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_windows_probe');
    first = p.join(root.path, 'First Tools');
    second = p.join(root.path, 'Second Tools');
    Directory(first).createSync();
    Directory(second).createSync();
    first = Directory(first).resolveSymbolicLinksSync();
    second = Directory(second).resolveSymbolicLinksSync();
    driver = File(p.join(root.path, 'probe.dart'))
      ..writeAsStringSync('''
import 'dart:convert';
import 'dart:io';
import 'package:dovetail_cli/src/doctor/doctor.dart';
Future<void> main(List<String> args) async {
  final report = await CommandProbe(name: args[0], purpose: 'native probe',
    trivialArguments: const ['--probe'],
    expectsFile: args.length > 1 ? 'artifact.out' : null).probe();
  print(jsonEncode({'status': report.status.name, 'path': report.path,
    'detail': report.detail}));
}
''');
  });

  tearDown(() => root.deleteSync(recursive: true));

  void unix(String directory) => File(
    p.join(directory, 'probe-tool'),
  ).writeAsStringSync('#!/bin/sh\nexit 0\n');

  void windows(
    String directory, {
    int exitCode = 0,
  }) => File(p.join(directory, 'probe-tool.cmd')).writeAsStringSync(
    '@echo off\r\necho native-probe\r\necho result > artifact.out\r\nexit /b $exitCode\r\n',
  );

  Map<String, dynamic> probe({
    String name = 'probe-tool',
    bool artifact = false,
  }) {
    final ProcessResult result = Process.runSync(
      Platform.resolvedExecutable,
      <String>[
        '--packages=${p.join(cli, '.dart_tool', 'package_config.json')}',
        driver.path,
        name,
        if (artifact) 'artifact',
      ],
      environment: <String, String>{
        'PATH':
            '$first;$second;${Platform.environment['SystemRoot']}\\System32',
      },
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    return jsonDecode(result.stdout as String) as Map<String, dynamic>;
  }

  test('Doctor uses a Windows launcher beside a Unix launcher', () {
    unix(first);
    windows(first);
    final Map<String, dynamic> result = probe(artifact: true);
    expect(result['status'], 'usable');
    expect(result['path'], p.join(first, 'probe-tool.cmd'));
  });

  test('a Unix-only PATH directory cannot hide a later Windows launcher', () {
    unix(first);
    windows(second);
    final Map<String, dynamic> result = probe();
    expect(result['status'], 'usable');
    expect(result['path'], p.join(second, 'probe-tool.cmd'));
  });

  test(
    'Doctor preserves PATH priority when the first Windows tool is broken',
    () {
      windows(first, exitCode: 17);
      windows(second);
      final Map<String, dynamic> result = probe();
      expect(result['status'], 'unusable');
      expect(result['path'], p.join(first, 'probe-tool.cmd'));
      expect(result['detail'], 'native-probe');
    },
  );

  test('a Unix launcher alone is absent from the native Windows toolchain', () {
    unix(first);
    expect(probe()['status'], 'absent');
  });

  test('an explicit Windows batch path still proves its artifact', () {
    windows(first);
    expect(
      probe(name: p.join(first, 'probe-tool.cmd'), artifact: true)['status'],
      'usable',
    );
  });
}
