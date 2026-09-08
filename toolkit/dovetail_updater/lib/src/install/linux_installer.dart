import 'dart:io';

import 'package:dovetail_updater/src/flow/verified_artifact.dart';
import 'package:dovetail_updater/src/install/linux_package_format.dart';
import 'package:dovetail_updater/src/install/update_installer.dart';
import 'package:dovetail_updater/src/update_failure.dart';
import 'package:path/path.dart' as p;
import 'package:dovetail_process_runner/dovetail_process_runner.dart';

final class LinuxInstaller implements UpdateInstaller {
  const LinuxInstaller({
    required this.runner,
    required this.appImagePath,
    this.pkexec = 'pkexec',
    this.dpkg = 'dpkg',
    this.rpm = 'rpm',
    this.chmod = 'chmod',
    this.scratchDirectory,
    this.processStatusFile = '/proc/self/status',
  });

  final ProcessRunner runner;
  final String appImagePath;
  final String pkexec;
  final String dpkg;
  final String rpm;
  final String chmod;
  final String? scratchDirectory;
  final String processStatusFile;

  @override
  Future<InstallOutcome> install(VerifiedArtifact artifact) async {
    final LinuxPackageFormat format = LinuxPackageFormat.of(artifact.fileName);
    return format.needsPrivilege
        ? _handToPackageManager(format, artifact)
        : _replaceAppImage(artifact);
  }

  List<String> argumentsFor(LinuxPackageFormat format, String packagePath) =>
      switch (format) {
        LinuxPackageFormat.debian => <String>[dpkg, '--install', packagePath],
        LinuxPackageFormat.rpm => <String>[
          rpm,
          '--upgrade',
          '--replacepkgs',
          packagePath,
        ],
        LinuxPackageFormat.appImage => throw StateError(
          'an AppImage is replaced in place, never through $pkexec',
        ),
      };

  Future<InstallOutcome> _replaceAppImage(VerifiedArtifact artifact) async {
    final File current = File(appImagePath);
    if (!current.existsSync()) {
      throw UpdateFailure(
        'there is no AppImage at $appImagePath to replace.',
        remedy:
            'LinuxInstaller replaces the file it was pointed at. Give it the '
            'path the running AppImage was launched from, which the process '
            'reads from the APPIMAGE environment variable.',
      );
    }

    final String backup = '$appImagePath.previous';
    if (File(backup).existsSync()) {
      File(backup).deleteSync();
    }
    current.renameSync(backup);

    try {
      File(appImagePath).writeAsBytesSync(artifact.bytes);
    } on FileSystemException catch (error) {
      File(backup).renameSync(appImagePath);
      throw UpdateFailure(
        'the new AppImage could not be written to $appImagePath.',
        remedy:
            'The previous one was put back, so the installation still runs. '
            '${error.osError?.message ?? error.message}',
      );
    }

    await _makeExecutable(appImagePath);
    File(backup).deleteSync();
    return InstallOutcome.installedRestartNeeded;
  }

  Future<InstallOutcome> _handToPackageManager(
    LinuxPackageFormat format,
    VerifiedArtifact artifact,
  ) async {
    final String? given = scratchDirectory;
    final Directory scratch = given == null
        ? Directory.systemTemp.createTempSync('dovetail_update')
        : (Directory(given)..createSync(recursive: true));
    final File package = File(p.join(scratch.path, artifact.fileName))
      ..writeAsBytesSync(artifact.bytes);

    final List<String> command = argumentsFor(format, package.path);
    final bool elevated = alreadyPrivileged();
    final ProcessOutcome applied = elevated
        ? await runner.run(command.first, command.sublist(1))
        : await runner.run(pkexec, command);
    scratch.deleteSync(recursive: true);

    if (!applied.succeeded) {
      throw UpdateFailure(
        'the package manager exited with ${applied.exitCode} instead of '
        'installing ${artifact.fileName}.',
        remedy: applied.stderr.trim().isEmpty
            ? elevated
                  ? 'Nothing was replaced, and this process is already root, '
                        'so no authorisation was asked for.'
                  : 'Nothing was replaced. $pkexec exits 126 when the '
                        'authorisation dialog is dismissed and 127 when it '
                        'cannot be shown at all, which is what happens over '
                        'ssh without a session bus.'
            : applied.stderr.trim(),
      );
    }

    return InstallOutcome.installedRestartNeeded;
  }

  bool alreadyPrivileged() {
    final File status = File(processStatusFile);
    if (!status.existsSync()) {
      return false;
    }
    for (final String line in status.readAsLinesSync()) {
      if (!line.startsWith('Uid:')) {
        continue;
      }
      final List<String> fields = line.split(RegExp(r'\s+'));
      return fields.length > 2 && fields[2] == '0';
    }
    return false;
  }

  Future<void> _makeExecutable(String path) async {
    final ProcessOutcome marked = await runner.run(chmod, <String>[
      '755',
      path,
    ]);
    if (!marked.succeeded) {
      throw UpdateFailure(
        'the new AppImage was written but could not be made executable.',
        remedy: 'Run: chmod 755 $path',
      );
    }
  }
}
