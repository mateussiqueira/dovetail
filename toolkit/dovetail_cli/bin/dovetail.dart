import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:dovetail_signer/dovetail_signer.dart';
import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:dovetail_cli/src/diagnostic/cli_log.dart';

const int _usageExit = 64;
const int _failureExit = 1;

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 &&
      (arguments.first == '--version' || arguments.first == '-v')) {
    stdout.writeln(DovetailVersion.line);
    exit(0);
  }

  final CommandRunner<int> runner =
      CommandRunner<int>('dovetail', 'The dovetail desktop toolkit.')
        ..addCommand(InitCommand())
        ..addCommand(DoctorCommand())
        ..addCommand(DevCommand())
        ..addCommand(BridgeCommand())
        ..addCommand(BuildCommand())
        ..addCommand(BundleCommand())
        ..addCommand(SignCommand())
        ..addCommand(IconCommand())
        ..addCommand(KeygenCommand())
        ..addCommand(InspectCommand())
        ..addCommand(ManifestCommand())
        ..addCommand(NewCommand())
        ..addCommand(ProbeCommand())
        ..addCommand(ReleaseCommand())
        ..addCommand(SelfInstallCommand())
        ..addCommand(SelfUpdateCommand())
        ..addCommand(ShipCommand())
        ..addCommand(UpdateCommand())
        ..addCommand(UpgradeCommand());

  try {
    exit(await runner.run(arguments) ?? 0);
  } on UsageException catch (error) {
    stderr.writeln(error);
    exit(_usageExit);
  } on ConfigFailure catch (error) {
    _report('config', error.message, error.remedy, where: error.origin);
  } on BundleFailure catch (error) {
    _report('bundle', error.message, error.remedy);
  } on SigningFailure catch (error) {
    _report('sign', error.message, error.remedy);
  } on UpdateFailure catch (error) {
    _report('update', error.message, error.remedy);
  } on FileSystemException catch (error) {
    _report(
      'file',
      '${error.message}: ${error.path ?? 'no path'}',
      error.osError?.message,
    );
  } on Object catch (error, trace) {
    CliLog().record(
      runtimeType: '${error.runtimeType}',
      message: '$error',
      stack: trace,
    );
    _report(
      'dovetail',
      'an unexpected ${error.runtimeType} escaped.',
      'This is a defect in dovetail, not in your project. Nothing later in '
          'the release ran.\n\n${trace.toString().trim()}',
    );
  }
}

Never _report(String stage, String message, String? remedy, {String? where}) {
  stderr.writeln(
    where == null ? '$stage: $message' : '$stage ($where): $message',
  );
  if (remedy != null && remedy.trim().isNotEmpty) {
    for (final String line in remedy.trim().split('\n')) {
      stderr.writeln('  $line');
    }
  }
  exit(_failureExit);
}
