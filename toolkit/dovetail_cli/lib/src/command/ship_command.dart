import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_cli/src/command/doctor_command.dart';
import 'package:dovetail_cli/src/config/config_locator.dart';
import 'package:dovetail_cli/src/config/dovetail_config.dart';
import 'package:dovetail_cli/src/config/pubspec_version.dart';
import 'package:dovetail_cli/src/ship/ship_plan.dart';
import 'package:dovetail_cli/src/ship/ship_step.dart';

final class ShipCommand extends Command<int> {
  ShipCommand() {
    argParser
      ..addFlag('build', defaultsTo: true, help: 'off reuses the last build')
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'prints the steps and runs none of them',
      )
      ..addOption('version', help: 'defaults to the version in pubspec.yaml')
      ..addOption('binary', help: 'defaults to the name in pubspec.yaml')
      ..addOption(
        'windows-format',
        allowed: <String>['nsis', 'msi'],
        defaultsTo: 'msi',
        help: 'msi builds on any host; nsis needs the ansi stub off Windows',
      );
  }

  @override
  String get name => 'ship';

  @override
  String get description =>
      'Runs the whole pipeline for this host, reading dovetail.yaml.';

  @override
  Future<int> run() async {
    final File? file = ConfigLocator.findFile();
    if (file == null) {
      throw UsageException(
        'no dovetail.yaml was found here or in any parent directory.',
        'ship reads everything from it, so there is nothing to read. Run: '
            'dovetail init\n\n$usage',
      );
    }

    final String root = ConfigLocator.rootFor(file);
    final DovetailConfig config = DovetailConfig.parse(
      file.readAsStringSync(),
      origin: file.path,
    );

    final ShipPlan plan = ShipPlan.of(
      config: config,
      version: argResults?.option('version') ?? PubspecVersion.read(root),
      host: hostTarget(),
      binary:
          argResults?.option('binary') ??
          PubspecVersion.nameOf(root) ??
          config.identifier.split('.').last,
      build: argResults?.flag('build') ?? true,
      windowsFormat: argResults?.option('windows-format'),
      environment: Platform.environment,
    );

    for (final ShipStep step in plan.steps) {
      stdout.writeln('→ ${step.label}');
    }
    stdout.writeln();

    // Antes do primeiro passo, e TAMBEM no dry-run.
    //
    // O que a esteira gasta antes de chegar ao `release` sao minutos —
    // `flutter build --release`, `codesign` sobre o bundle, `hdiutil`. Uma
    // condicao que o `dovetail.yaml` responde em milissegundos nao pode ser
    // descoberta depois disso.
    //
    // No dry-run porque a ajuda dele diz "imprime os passos e nao roda
    // nenhum", e quem le um dry-run verde entende "este plano funciona". Sair
    // 0 sobre um plano cujo ultimo passo recusa e a forma mais cara de mentir
    // que este comando tem.
    if (plan.refusals.isNotEmpty) {
      for (final String refusal in plan.refusals) {
        stderr.writeln('ship: $refusal');
      }
      stderr.writeln(
        'Nothing ran. These are checked from the config, before the build, '
        'because the build is the slow half.',
      );
      return 1;
    }

    if (argResults?.flag('dry-run') ?? false) {
      for (final ShipStep step in plan.steps) {
        stdout.writeln('dovetail $step');
      }
      return 0;
    }

    final CommandRunner<int>? through = runner;
    if (through == null) {
      throw StateError(
        'ship invokes the other commands through the runner it was added to, '
        'and it was not added to one',
      );
    }

    for (final ShipStep step in plan.steps) {
      stdout.writeln('── ${step.label} ──');
      final int outcome = await through.run(step.invocation) ?? 0;
      if (outcome != 0) {
        stderr.writeln(
          '${step.label} exited with $outcome; nothing after it '
          'ran',
        );
        return outcome;
      }
    }

    stdout.writeln();
    plan.artifacts.forEach((String key, String path) {
      stdout.writeln('$key  $path');
    });
    plan.downloads.forEach((String key, String path) {
      stdout.writeln('$key  $path  (download page; not in the manifest)');
    });
    return 0;
  }
}
