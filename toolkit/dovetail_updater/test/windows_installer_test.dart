import 'dart:io';
import 'dart:typed_data';

import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:test/test.dart';

VerifiedArtifact artifactNamed(String name) => VerifiedArtifact.trusted(
  bytes: Uint8List.fromList(<int>[0x4D, 0x5A, 0x90, 0x00]),
  sourceUrl: 'https://cdn.example.com/releases/$name',
  trustedComment: 'version:2.1.0\tfile:$name',
);

final class _RecordingLauncher implements ProcessLauncher {
  String? executable;
  List<String> arguments = const <String>[];
  int launches = 0;

  @override
  Future<int> launch(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    this.executable = executable;
    this.arguments = arguments;
    launches++;
    return 4242;
  }
}

final class _Recording implements ProcessRunner {
  String? executable;
  List<String> arguments = const <String>[];
  int exitCode = 0;
  String stderr = '';

  @override
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdin,
    Duration? timeout,
  }) async {
    this.executable = executable;
    this.arguments = arguments;
    return ProcessOutcome(exitCode: exitCode, stdout: '', stderr: stderr);
  }
}

void main() {
  group('VerifiedArtifact.fileName', () {
    test('should be the last segment of the url it came from', () {
      expect(
        artifactNamed('client_2.1.0_x64_setup.exe').fileName,
        'client_2.1.0_x64_setup.exe',
      );
    });

    test('should survive a query string', () {
      expect(
        VerifiedArtifact.trusted(
          bytes: Uint8List(0),
          sourceUrl: 'https://cdn/a/client.exe?token=abc&v=2',
          trustedComment: '',
        ).fileName,
        'client.exe',
      );
    });

    test('should not be empty when the url has no path', () {
      expect(
        VerifiedArtifact.trusted(
          bytes: Uint8List(0),
          sourceUrl: 'https://cdn.example.com',
          trustedComment: '',
        ).fileName,
        'update',
      );
    });
  });

  group('the installer it was handed', () {
    test('an msi should run through msiexec and finish', () async {
      final _Recording runner = _Recording();

      expect(
        await WindowsInstaller(
          runner: runner,
        ).install(artifactNamed('client_2.1.0_x64.msi')),
        InstallOutcome.installedRestartNeeded,
        reason:
            'msiexec runs to completion, so the outcome is an installation '
            'that happened, not an installer that took over',
      );
      expect(runner.executable, 'msiexec');
      expect(runner.arguments.first, '/i');
      expect(runner.arguments[1], endsWith('client_2.1.0_x64.msi'));
      expect(runner.arguments, contains('/norestart'));
    });

    test('an exe should be launched and never awaited', () async {
      final _Recording runner = _Recording();
      final _RecordingLauncher launcher = _RecordingLauncher();

      expect(
        await WindowsInstaller(
          runner: runner,
          launcher: launcher,
        ).install(artifactNamed('client_2.1.0_x64_setup.exe')),
        InstallOutcome.installerLaunchedAppMustExit,
      );
      expect(launcher.launches, 1);
      expect(launcher.executable, endsWith('client_2.1.0_x64_setup.exe'));
      expect(
        runner.executable,
        isNull,
        reason:
            'an NSIS installer waits for the running app to close before it '
            'can replace it, so awaiting it from inside that app is a wait '
            'with no end',
      );
    });

    test('an exe with no launcher should refuse, not deadlock', () async {
      await expectLater(
        WindowsInstaller(
          runner: _Recording(),
        ).install(artifactNamed('setup.exe')),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.remedy,
            'remedy',
            contains('wait with no end'),
          ),
        ),
      );
    });

    test('an archive should be refused by name', () async {
      await expectLater(
        WindowsInstaller(
          runner: _Recording(),
        ).install(artifactNamed('client.zip')),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.message,
            'message',
            contains('client.zip'),
          ),
        ),
      );
    });
  });

  group('the exit codes msiexec actually uses', () {
    test('3010 and 1641 are successes that ask for a reboot', () async {
      for (final int code in <int>[0, 3010, 1641]) {
        final _Recording runner = _Recording()..exitCode = code;

        expect(
          await WindowsInstaller(
            runner: runner,
          ).install(artifactNamed('client.msi')),
          InstallOutcome.installedRestartNeeded,
          reason:
              'treating $code as failure tells the user the update failed '
              'after it already replaced the application on disk',
        );
      }
    });

    test('installed() should name the two reboot codes', () {
      expect(WindowsInstaller.rebootRequired, 3010);
      expect(WindowsInstaller.rebootInitiated, 1641);
      expect(WindowsInstaller.installed(0), true);
      expect(WindowsInstaller.installed(3010), true);
      expect(WindowsInstaller.installed(1641), true);
      expect(WindowsInstaller.installed(1602), false);
      expect(WindowsInstaller.installed(1603), false);
    });

    test('a real failure should still surface with its code', () async {
      final _Recording runner = _Recording()..exitCode = 1602;

      await expectLater(
        WindowsInstaller(runner: runner).install(artifactNamed('client.msi')),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.message,
            'message',
            contains('1602'),
          ),
        ),
        reason: '1602 is the user cancelling the install',
      );
    });

    test(
      'a failure should say the installed application is untouched',
      () async {
        final _Recording runner = _Recording()..exitCode = 1603;

        await expectLater(
          WindowsInstaller(runner: runner).install(artifactNamed('client.msi')),
          throwsA(
            isA<UpdateFailure>().having(
              (UpdateFailure failure) => failure.remedy,
              'remedy',
              contains('untouched'),
            ),
          ),
        );
      },
    );

    test('what msiexec printed should reach the caller', () async {
      final _Recording runner = _Recording()
        ..exitCode = 1603
        ..stderr = 'Another installation is already in progress.';

      await expectLater(
        WindowsInstaller(runner: runner).install(artifactNamed('client.msi')),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.remedy,
            'remedy',
            contains('already in progress'),
          ),
        ),
      );
    });
  });

  group('the executable each format needs', () {
    test('an msi is data, so msiexec runs and the msi is an argument', () {
      const WindowsInstaller installer = WindowsInstaller(
        runner: SystemProcessRunner(),
      );

      expect(installer.executableFor('.msi', 'C:/t/app.msi'), 'msiexec');
      expect(installer.argumentsFor('.msi', 'C:/t/app.msi').first, '/i');
      expect(
        installer.argumentsFor('.msi', 'C:/t/app.msi'),
        contains('C:/t/app.msi'),
      );
    });

    test('an exe is a program, so it runs itself', () {
      const WindowsInstaller installer = WindowsInstaller(
        runner: SystemProcessRunner(),
      );

      expect(
        installer.executableFor('.exe', 'C:/t/setup.exe'),
        'C:/t/setup.exe',
      );
    });

    test('each mode should pass the NSIS flags it means', () {
      List<String> flagsFor(WindowsInstallMode mode) => WindowsInstaller(
        runner: const SystemProcessRunner(),
        mode: mode,
      ).argumentsFor('.exe', 'C:/t/setup.exe');

      expect(flagsFor(WindowsInstallMode.passive), <String>['/P', '/R']);
      expect(flagsFor(WindowsInstallMode.quiet), <String>['/S', '/R']);
      expect(flagsFor(WindowsInstallMode.interactive), isEmpty);
    });

    test('quiet and passive should each reach msiexec once', () {
      List<String> msiFlags(WindowsInstallMode mode) => WindowsInstaller(
        runner: const SystemProcessRunner(),
        mode: mode,
      ).argumentsFor('.msi', 'C:/t/app.msi');

      expect(msiFlags(WindowsInstallMode.quiet), contains('/quiet'));
      expect(msiFlags(WindowsInstallMode.passive), contains('/passive'));
      expect(
        msiFlags(WindowsInstallMode.interactive),
        isNot(anyOf(contains('/quiet'), contains('/passive'))),
      );
    });
  });

  group('what is left behind in the scratch directory', () {
    late Directory scratch;

    setUp(() {
      scratch = Directory.systemTemp.createTempSync('dovetail_test');
      addTearDown(() {
        if (scratch.existsSync()) scratch.deleteSync(recursive: true);
      });
    });

    test('an awaited msi should leave no file behind', () async {
      // msiexec was awaited, so the installer has been read. Before this the
      // MSI path returned without deleting, and every test run left the
      // package in the host's temp directory — 81 of them were found there.
      await WindowsInstaller(
        runner: _Recording(),
        scratchDirectory: scratch.path,
      ).install(artifactNamed('client_2.1.0_x64.msi'));

      expect(scratch.existsSync(), false);
    });

    test('an msi that fails should still clean up', () async {
      final _Recording runner = _Recording()..exitCode = 1603;

      await expectLater(
        WindowsInstaller(
          runner: runner,
          scratchDirectory: scratch.path,
        ).install(artifactNamed('client_2.1.0_x64.msi')),
        throwsA(isA<UpdateFailure>()),
      );

      expect(scratch.existsSync(), false);
    });

    test(
      'a detached exe must keep its file, because the installer is still reading it',
      () async {
        // The opposite invariant, pinned so nobody "fixes" the leak here: NSIS
        // is launched and never awaited, and it reads its own file after this
        // process has returned. Deleting it would hand the user an installer
        // that vanished under it.
        await WindowsInstaller(
          runner: _Recording(),
          launcher: _RecordingLauncher(),
          scratchDirectory: scratch.path,
        ).install(artifactNamed('client_2.1.0_x64.exe'));

        expect(scratch.existsSync(), true);
        expect(
          scratch.listSync().single.path,
          endsWith('client_2.1.0_x64.exe'),
        );
      },
    );
  });
}
