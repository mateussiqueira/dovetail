import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/package_tool.dart';

void main() {
  late Directory directory;
  late Map<String, String> environment;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('verify runner ');
    final File launcher = File(
      '${directory.path}/${Platform.isWindows ? 'flutter.bat' : 'flutter'}',
    );
    launcher.writeAsStringSync(
      Platform.isWindows
          ? '@echo off\r\necho %~1\r\necho %~2\r\necho %DOVETAIL_REPO_ROOT%\r\nexit /b 7\r\n'
          : '#!/bin/sh\nprintf "%s\\n" "\$1" "\$2" "\$DOVETAIL_REPO_ROOT"\nexit 7\n',
    );
    if (!Platform.isWindows) {
      expect(
        Process.runSync('chmod', <String>['+x', launcher.path]).exitCode,
        0,
      );
    }
    environment = <String, String>{
      'PATH':
          '${directory.path}${Platform.isWindows ? ';' : ':'}${Platform.environment['PATH']}',
      'DOVETAIL_REPO_ROOT': directory.path,
    };
  });

  tearDown(() => directory.deleteSync(recursive: true));

  void verify(ProcessResult result) {
    expect(result.exitCode, 7);
    expect(result.stdout.toString().split(RegExp(r'\r?\n')).take(3), <String>[
      'argument with spaces',
      '--json',
      directory.path,
    ]);
  }

  test('sync verifier launches the platform Flutter entry point', () {
    verify(
      runPackageToolSync(
        'flutter',
        <String>['argument with spaces', '--json'],
        workingDirectory: directory.path,
        environment: environment,
      ),
    );
  });

  test(
    'async verifier preserves Flutter arguments environment and exit code',
    () async {
      verify(
        await runPackageTool(
          'flutter',
          <String>['argument with spaces', '--json'],
          workingDirectory: directory.path,
          environment: environment,
        ),
      );
    },
  );

  test('native Dart executable remains directly launchable', () async {
    final ProcessResult result = await runPackageTool(
      Platform.resolvedExecutable,
      <String>['--version'],
      workingDirectory: directory.path,
    );
    expect(result.exitCode, 0);
    expect(result.stdout.toString(), contains('Dart SDK version'));
  });
}
