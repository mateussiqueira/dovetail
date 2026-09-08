import 'dart:io';

import 'package:dovetail_updater/src/flow/verified_artifact.dart';
import 'package:dovetail_updater/src/install/update_installer.dart';
import 'package:dovetail_process_runner/dovetail_process_runner.dart';
import 'package:dovetail_updater/src/update_failure.dart';
import 'package:path/path.dart' as p;

final class MacosInstaller implements UpdateInstaller {
  const MacosInstaller({
    required this.runner,
    required this.bundlePath,
    this.tar = 'tar',
    this.osascript = 'osascript',
    this.touch = 'touch',
  });

  final ProcessRunner runner;
  final String bundlePath;
  final String tar;
  final String osascript;
  final String touch;

  @override
  Future<InstallOutcome> install(VerifiedArtifact artifact) async {
    final Directory current = Directory(bundlePath);
    if (!current.existsSync()) {
      throw UpdateFailure('there is no bundle at $bundlePath to replace.');
    }

    final Directory scratch = Directory.systemTemp.createTempSync(
      'dovetail_up',
    );
    final File archive = File(p.join(scratch.path, 'update.tar.gz'))
      ..writeAsBytesSync(artifact.bytes);

    final ProcessOutcome extracted = await runner.run(tar, <String>[
      '-xzf',
      archive.path,
      '-C',
      scratch.path,
    ]);
    if (!extracted.succeeded) {
      scratch.deleteSync(recursive: true);
      throw UpdateFailure(
        'could not extract the update archive.',
        remedy: extracted.stderr.trim(),
      );
    }

    final String? incoming = _findBundle(scratch);
    if (incoming == null) {
      scratch.deleteSync(recursive: true);
      throw const UpdateFailure(
        'the archive carries no .app bundle.',
        remedy: 'Nothing was replaced.',
      );
    }

    final String backup = '$bundlePath.previous';
    if (Directory(backup).existsSync()) {
      Directory(backup).deleteSync(recursive: true);
    }

    try {
      current.renameSync(backup);
      Directory(incoming).renameSync(bundlePath);
    } on FileSystemException {
      await _swapWithAdministrator(incoming, backup);
    }

    await runner.run(touch, <String>[bundlePath]);
    if (Directory(backup).existsSync()) {
      Directory(backup).deleteSync(recursive: true);
    }
    scratch.deleteSync(recursive: true);

    return InstallOutcome.installedRestartNeeded;
  }

  Future<void> _swapWithAdministrator(String incoming, String backup) async {
    if (Directory(backup).existsSync() && !Directory(bundlePath).existsSync()) {
      Directory(backup).renameSync(bundlePath);
    }

    final String script =
        'do shell script "rm -rf \\"$bundlePath\\" && '
        'mv -f \\"$incoming\\" \\"$bundlePath\\"" '
        'with administrator privileges';

    final ProcessOutcome elevated = await runner.run(osascript, <String>[
      '-e',
      script,
    ]);
    if (!elevated.succeeded) {
      throw const UpdateFailure(
        'the privileged swap was refused.',
        remedy: 'The installed application was left untouched.',
      );
    }
  }

  String? _findBundle(Directory scratch) {
    for (final FileSystemEntity entity in scratch.listSync()) {
      if (entity is Directory && p.extension(entity.path) == '.app') {
        return entity.path;
      }
    }
    return null;
  }
}
