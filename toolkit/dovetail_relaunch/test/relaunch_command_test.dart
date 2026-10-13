import 'dart:convert';
import 'dart:io';

import 'package:dovetail_relaunch/dovetail_relaunch.dart';
import 'package:test/test.dart';

String _powershellScript(RelaunchCommand command) {
  final List<int> bytes = base64.decode(command.arguments.last);
  return String.fromCharCodes(<int>[
    for (int index = 0; index < bytes.length; index += 2)
      bytes[index] | bytes[index + 1] << 8,
  ]);
}

void main() {
  group('on macOS', () {
    test('should reopen the bundle, not the binary inside it', () {
      final RelaunchCommand command = RelaunchCommand.forHost(
        operatingSystem: 'macos',
        executable: '/Applications/Probe.app/Contents/MacOS/Probe',
        pid: 42,
        arguments: <String>['--after-update'],
      );

      expect(command.executable, '/bin/sh');
      expect(command.arguments.skip(2), <String>[
        '42',
        '/usr/bin/open',
        '-n',
        '/Applications/Probe.app',
        '--args',
        '--after-update',
      ]);
    });

    test('should not pass --args when there is nothing to pass', () {
      final RelaunchCommand command = RelaunchCommand.forHost(
        operatingSystem: 'macos',
        executable: '/Applications/Probe.app/Contents/MacOS/Probe',
        pid: 42,
      );

      expect(command.arguments.skip(2), <String>[
        '42',
        '/usr/bin/open',
        '-n',
        '/Applications/Probe.app',
      ]);
    });

    test('should start the binary itself when it is not in a bundle', () {
      final RelaunchCommand command = RelaunchCommand.forHost(
        operatingSystem: 'macos',
        executable: '/usr/local/bin/probe',
        pid: 42,
        arguments: <String>['--after-update'],
      );

      expect(command.arguments.skip(2), <String>[
        '42',
        '/usr/local/bin/probe',
        '--after-update',
      ]);
    });
  });

  group('on Linux', () {
    test('should start the AppImage the app was mounted from', () {
      final RelaunchCommand command = RelaunchCommand.forHost(
        operatingSystem: 'linux',
        executable: '/tmp/.mount_Probe/usr/bin/probe',
        pid: 42,
        arguments: <String>['--after-update'],
        environment: <String, String>{'APPIMAGE': '/opt/Probe.AppImage'},
      );

      expect(command.executable, '/bin/sh');
      expect(command.arguments.skip(2), <String>[
        '42',
        '/opt/Probe.AppImage',
        '--after-update',
      ]);
    });

    test('should start the binary when APPIMAGE is empty', () {
      final RelaunchCommand command = RelaunchCommand.forHost(
        operatingSystem: 'linux',
        executable: '/usr/bin/probe',
        pid: 42,
        environment: <String, String>{'APPIMAGE': ''},
      );

      expect(command.arguments.skip(2), <String>['42', '/usr/bin/probe']);
    });
  });

  group('on Windows', () {
    test('should wait for the old pid, then start the same executable', () {
      final RelaunchCommand command = RelaunchCommand.forHost(
        operatingSystem: 'windows',
        executable: r'C:\Program Files\Probe\probe.exe',
        pid: 42,
      );

      expect(command.executable, 'powershell.exe');
      expect(
        _powershellScript(command),
        'Wait-Process -Id 42 -ErrorAction SilentlyContinue; '
        r"Start-Process -FilePath 'C:\Program Files\Probe\probe.exe'",
      );
    });

    test('should quote each argument the way Windows splits it', () {
      final RelaunchCommand command = RelaunchCommand.forHost(
        operatingSystem: 'windows',
        executable: r'C:\Probe\probe.exe',
        pid: 42,
        arguments: <String>[
          'plain',
          'two words',
          'say "hi"',
          r'C:\my dir\',
          r'a\"b',
          '',
        ],
      );

      expect(
        _powershellScript(command),
        'Wait-Process -Id 42 -ErrorAction SilentlyContinue; '
        r"Start-Process -FilePath 'C:\Probe\probe.exe' -ArgumentList "
        r"""'plain "two words" "say \"hi\"" "C:\my dir\\" "a\\\"b" ""'""",
      );
    });

    test('should double a single quote inside a PowerShell literal', () {
      final RelaunchCommand command = RelaunchCommand.forHost(
        operatingSystem: 'windows',
        executable: r"C:\Users\O'Neil\probe.exe",
        pid: 42,
      );

      expect(
        _powershellScript(command),
        endsWith(r"-FilePath 'C:\Users\O''Neil\probe.exe'"),
      );
    });
  });

  test(
    'the new process should start only once the old pid is gone',
    () async {
      final Directory directory = Directory.systemTemp.createTempSync(
        'relaunch_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final String started = '${directory.path}/started';
      final Process old = await Process.start('sleep', <String>['30']);
      final RelaunchCommand command = RelaunchCommand.forHost(
        operatingSystem: 'linux',
        executable: 'touch',
        pid: old.pid,
        arguments: <String>[started],
      );

      await Process.start(command.executable, command.arguments);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final bool startedEarly = File(started).existsSync();
      old.kill(ProcessSignal.sigkill);
      await old.exitCode;
      final Stopwatch waited = Stopwatch()..start();
      while (!File(started).existsSync() && waited.elapsed.inSeconds < 10) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(startedEarly, isFalse);
      expect(File(started).existsSync(), isTrue);
    },
    testOn: '!windows',
  );
}
