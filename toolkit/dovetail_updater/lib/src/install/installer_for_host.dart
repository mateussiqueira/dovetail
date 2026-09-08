import 'dart:io';

import 'package:dovetail_updater/src/install/linux_installer.dart';
import 'package:dovetail_updater/src/install/macos_installer.dart';
import 'package:dovetail_updater/src/install/update_installer.dart';
import 'package:dovetail_updater/src/install/windows_installer.dart';
import 'package:dovetail_updater/src/update_failure.dart';
import 'package:path/path.dart' as p;
import 'package:dovetail_process_runner/dovetail_process_runner.dart';

final class InstallerForHost {
  const InstallerForHost._();

  static UpdateInstaller resolve({
    required ProcessRunner runner,
    required String installedPath,
    ProcessLauncher? launcher,
    String? operatingSystem,
  }) {
    final String host = operatingSystem ?? Platform.operatingSystem;
    return switch (host) {
      'macos' => MacosInstaller(
        runner: runner,
        bundlePath: _bundleOf(installedPath),
      ),
      'windows' => WindowsInstaller(runner: runner, launcher: launcher),
      'linux' => LinuxInstaller(runner: runner, appImagePath: installedPath),
      final String other => throw UpdateFailure(
        'there is no installer for $other.',
        remedy:
            'A client that downloads and verifies an update it cannot apply '
            'has told the user a new version is ready and then done nothing '
            'with it. This refuses before the download instead.',
      ),
    };
  }

  static String _bundleOf(String installedPath) {
    String candidate = installedPath;
    while (p.extension(candidate) != '.app') {
      final String parent = p.dirname(candidate);
      if (parent == candidate) {
        return installedPath;
      }
      candidate = parent;
    }
    return candidate;
  }

  static String installedPathForHost() {
    if (Platform.isLinux) {
      final String? appImage = Platform.environment['APPIMAGE'];
      if (appImage == null || appImage.isEmpty) {
        throw const UpdateFailure(
          'APPIMAGE is not set, so this is not a running AppImage.',
          remedy:
              'A .deb or .rpm install is replaced by the package manager and '
              'needs no path; an AppImage replaces the file it was launched '
              'from, which the runtime puts in APPIMAGE.',
        );
      }
      return appImage;
    }
    return Platform.resolvedExecutable;
  }
}
