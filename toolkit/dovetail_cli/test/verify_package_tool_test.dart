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

  List<String> installBash() {
    if (Platform.isWindows) {
      File(
        '${Platform.environment['SystemRoot']}/System32/cmd.exe',
      ).copySync('${directory.path}/bash.exe');
      return <String>['/d', '/c', 'exit /b 7'];
    }
    final File script = File('${directory.path}/bash')
      ..writeAsStringSync('#!/bin/sh\nexit 7\n');
    expect(Process.runSync('chmod', <String>['+x', script.path]).exitCode, 0);
    return <String>[];
  }

  test('sync gate selects Bash from its PATH instead of the WSL launcher', () {
    expect(
      runPackageToolSync(
        'bash',
        installBash(),
        environment: environment,
      ).exitCode,
      7,
    );
  });

  test('async gate preserves the native Bash exit code', () async {
    expect(
      (await runPackageTool(
        'bash',
        installBash(),
        environment: environment,
      )).exitCode,
      7,
    );
  });

  test(
    'a WSL-only PATH is refused instead of running checks on another host',
    () {
      expect(
        () => selectNativeBashExecutable(<String>[
          r'C:\WINDOWS\System32\bash.exe',
        ], r'C:\Windows'),
        throwsA(isA<ProcessException>()),
      );
    },
  );

  test('native Bash selection preserves PATH order and ignores WSL', () {
    expect(
      selectNativeBashExecutable(<String>[
        r'C:\Windows\System32\bash.exe',
        r'D:\Portable Git\bin\bash.exe',
        r'C:\Program Files\Git\bin\bash.exe',
      ], r'C:\Windows'),
      r'D:\Portable Git\bin\bash.exe',
    );
  });

  File unicodeTool() =>
      File('${directory.path}/unicode.dart')..writeAsStringSync(
        "import 'dart:io'; import 'dart:convert'; "
        "void main() { stdout.add(utf8.encode('núcleo 核')); "
        "stderr.add(utf8.encode('verificação ✅')); }",
      );

  void verifyUnicode(ProcessResult result) {
    expect(result.exitCode, 0);
    expect(result.stdout, 'núcleo 核');
    expect(result.stderr, 'verificação ✅');
  }

  test('sync gate decodes tool output as UTF-8 on every host', () {
    verifyUnicode(
      runPackageToolSync(Platform.resolvedExecutable, <String>[
        unicodeTool().path,
      ]),
    );
  });

  test('async gate decodes tool output as UTF-8 on every host', () async {
    verifyUnicode(
      await runPackageTool(Platform.resolvedExecutable, <String>[
        unicodeTool().path,
      ]),
    );
  });
}
