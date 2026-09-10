import 'dart:io';

import 'package:dovetail_updater/src/flow/verified_artifact.dart';
import 'package:dovetail_updater/src/install/update_installer.dart';
import 'package:dovetail_process_runner/dovetail_process_runner.dart';
import 'package:dovetail_updater/src/update_failure.dart';
import 'package:path/path.dart' as p;

enum WindowsInstallMode {
  passive(<String>['/P', '/R']),
  quiet(<String>['/S', '/R']),
  interactive(<String>[]);

  const WindowsInstallMode(this.nsisArguments);

  final List<String> nsisArguments;
}

final class WindowsInstaller implements UpdateInstaller {
  const WindowsInstaller({
    required this.runner,
    this.launcher,
    this.mode = WindowsInstallMode.passive,
    this.scratchDirectory,
    this.msiexec = 'msiexec',
  });

  final ProcessRunner runner;
  final ProcessLauncher? launcher;
  final WindowsInstallMode mode;
  final String? scratchDirectory;
  final String msiexec;

  static const Set<String> installerExtensions = <String>{'.exe', '.msi'};

  static const int rebootRequired = 3010;
  static const int rebootInitiated = 1641;

  static bool installed(int exitCode) =>
      exitCode == 0 ||
      exitCode == rebootRequired ||
      exitCode == rebootInitiated;

  @override
  Future<InstallOutcome> install(VerifiedArtifact artifact) async {
    final String extension = p.extension(artifact.fileName).toLowerCase();
    if (!installerExtensions.contains(extension)) {
      throw UpdateFailure(
        'the artefact is "${artifact.fileName}", which is not an installer '
        'this can run.',
        remedy:
            'On Windows an update is the installer itself, run over the '
            'installation in place. Publish the .exe or the .msi as the '
            'update artefact, not an archive of the app directory.',
      );
    }

    final Directory scratch = scratchDirectory == null
        ? Directory.systemTemp.createTempSync('dovetail_update')
        : (Directory(scratchDirectory!)..createSync(recursive: true));

    final File installer = File(p.join(scratch.path, artifact.fileName))
      ..writeAsBytesSync(artifact.bytes);

    final String executable = executableFor(extension, installer.path);
    final List<String> arguments = argumentsFor(extension, installer.path);

    if (extension != '.msi') {
      final ProcessLauncher? detached = launcher;
      if (detached == null) {
        throw const UpdateFailure(
          'no launcher was given for an installer that takes over.',
          remedy:
              'An NSIS installer waits for the running application to close '
              'before it can replace it, so awaiting the installer from inside '
              'that application is a wait with no end. Pass a ProcessLauncher.',
        );
      }
      await detached.launch(executable, arguments);
      return InstallOutcome.installerLaunchedAppMustExit;
    }

    final ProcessOutcome finished;
    try {
      finished = await runner.run(executable, arguments);
    } finally {
      // msiexec was AWAITED, so the file has been read by the time we are
      // here, whichever way it went. The detached branch above deliberately
      // does not do this: an NSIS installer is still reading its own file
      // after this process has returned, and deleting it would hand the user
      // an installer that vanished under it.
      scratch.deleteSync(recursive: true);
    }
    if (!installed(finished.exitCode)) {
      throw UpdateFailure(
        'msiexec exited with ${finished.exitCode} and installed nothing.',
        remedy: finished.stderr.trim().isEmpty
            ? 'Nothing was replaced. The installed application is untouched.'
            : finished.stderr.trim(),
      );
    }

    return InstallOutcome.installedRestartNeeded;
  }

  String executableFor(String extension, String installerPath) =>
      extension == '.msi' ? msiexec : installerPath;

  List<String> argumentsFor(String extension, String installerPath) =>
      switch (extension) {
        '.msi' => <String>[
          '/i',
          installerPath,
          if (mode == WindowsInstallMode.quiet) '/quiet',
          if (mode == WindowsInstallMode.passive) '/passive',
          '/norestart',
        ],
        _ => mode.nsisArguments,
      };
}
