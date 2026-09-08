import 'dart:io';

import 'package:args/args.dart';
import 'package:dovetail_bundler/dovetail_bundler.dart';

Future<void> main(List<String> arguments) async {
  final ArgParser parser = ArgParser()
    ..addOption('target', allowed: <String>['windows'], defaultsTo: 'windows')
    ..addOption('product-name', mandatory: true)
    ..addOption('manufacturer', mandatory: true)
    ..addOption('identifier', mandatory: true)
    ..addOption('version', mandatory: true)
    ..addOption('main-binary', mandatory: true)
    ..addOption('app-dir', mandatory: true)
    ..addOption('out-dir', mandatory: true)
    ..addOption(
      'arch',
      allowed: <String>['x86_64', 'arm64'],
      defaultsTo: 'x86_64',
      help: 'x86_64 covers every Intel and AMD desktop',
    )
    ..addOption('makensis', defaultsTo: 'makensis')
    ..addOption('plugin-dir', defaultsTo: '')
    ..addOption('hooks')
    ..addOption('icon')
    ..addOption('license')
    ..addOption('homepage')
    ..addOption(
      'install-mode',
      allowed: <String>['per-machine', 'current-user'],
      defaultsTo: 'per-machine',
    )
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exit(64);
  }

  if (args.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }

  try {
    final BundleSpec spec = BundleSpec(
      productName: args.option('product-name')!,
      manufacturer: args.option('manufacturer')!,
      identifier: args.option('identifier')!,
      version: AppVersion.parse(args.option('version')!),
      mainBinaryName: args.option('main-binary')!,
      appDirectory: args.option('app-dir')!,
      outputDirectory: args.option('out-dir')!,
      installMode: args.option('install-mode') == 'current-user'
          ? InstallMode.currentUser
          : InstallMode.perMachine,
      installerHooks: args.option('hooks'),
      installerIcon: args.option('icon'),
      licenseFile: args.option('license'),
      homepage: args.option('homepage'),
    );

    final String pluginDirectory = args.option('plugin-dir')!.isEmpty
        ? Directory.systemTemp.createTempSync('dovetail_plugins').path
        : args.option('plugin-dir')!;

    final String installer = await NsisBundler(
      runner: const SystemProcessRunner(),
      makensis: args.option('makensis')!,
      pluginDirectory: pluginDirectory,
      arch: TargetArch.parse(args.option('arch')!),
    ).bundle(spec);

    stdout.writeln(installer);
  } on BundleFailure catch (failure) {
    stderr.writeln(failure.toString());
    exit(1);
  }
}
