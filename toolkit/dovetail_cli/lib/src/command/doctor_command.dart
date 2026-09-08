import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:dovetail_cli/src/config/config_locator.dart';
import 'package:dovetail_cli/src/config/dovetail_config.dart';
import 'package:dovetail_cli/src/config/pubspec_version.dart';
import 'package:dovetail_cli/src/doctor/app_report.dart';
import 'package:dovetail_cli/src/doctor/binary_report.dart';
import 'package:dovetail_cli/src/doctor/doctor.dart';
import 'package:dovetail_cli/src/doctor/project_report.dart';
import 'package:dovetail_cli/src/doctor/sdk_report.dart';
import 'package:dovetail_cli/src/doctor/spm_report.dart';
import 'package:dovetail_cli/src/doctor/target_key.dart';
import 'package:dovetail_cli/src/doctor/tool_probe.dart';
import 'package:dovetail_cli/src/dovetail_version.dart';
import 'package:dovetail_cli/src/sdk/sdk_channel.dart';
import 'package:dovetail_cli/src/sdk/sdk_locator.dart';
import 'package:dovetail_cli/src/sdk/version_order.dart';

const List<String> knownTargets = <String>['windows', 'macos', 'linux'];

String hostTarget() {
  if (Platform.isWindows) {
    return 'windows';
  }
  if (Platform.isMacOS) {
    return 'macos';
  }
  return 'linux';
}

final class DoctorCommand extends Command<int> {
  final SdkLocator? _sdkLocator;
  final ArtifactFetcher? _fetcher;

  DoctorCommand({this._sdkLocator, this._fetcher}) {
    argParser
      ..addOption('target', allowed: knownTargets, help: 'defaults to the host')
      ..addOption(
        'arch',
        allowed: <String>['x86_64', 'arm64'],
        help:
            'also reports whether cargo can build for this target; x86_64 '
            'covers every Intel and AMD desktop',
      )
      ..addFlag(
        'check-updates',
        help:
            'also compare the installed SDK against the channel latest '
            '(needs network)',
      )
      ..addOption(
        'base-url',
        help:
            'the release channel root; defaults to '
            '${SdkChannel.installUrlEnv}',
      );
  }

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Reports which platform tools are present and actually usable.';

  @override
  Future<int> run() async {
    final int projectOutcome = _reportProject();
    _reportSdk();
    _reportBinary();
    _reportApp();
    _reportSpm();
    await _reportUpdateCheck();
    final List<TargetKey> requested = _requested();
    int worst = projectOutcome;

    for (final TargetKey target in requested) {
      final List<ToolReport> reports = await Doctor.run(
        Doctor.probesFor(target.os, arch: target.arch),
      );

      stdout
        ..writeln(
          target.arch == null
              ? 'target: ${target.os}'
              : 'target: ${target.platformKey}',
        )
        ..writeln(Doctor.render(reports));

      final int outcome = _outcomeOf(reports);
      if (outcome > worst) {
        worst = outcome;
      }
      if (target != requested.last) {
        stdout.writeln();
      }
    }

    return worst;
  }

  int _reportProject() {
    if (argResults?.option('target') != null) {
      return 0;
    }

    final File? file = ConfigLocator.findFile();
    final ProjectReport report = ProjectReport.of(
      config: file == null
          ? null
          : DovetailConfig.parse(file.readAsStringSync(), origin: file.path),
      version: file == null ? null : _versionBeside(file),
      host: hostTarget(),
      environment: Platform.environment,
    );

    stdout.writeln('project');
    for (final ProjectNote note in report.notes) {
      stdout.writeln('  ${note.line}');
    }
    stdout.writeln();

    return report.shipCanRelease ? 0 : 2;
  }

  String? _versionBeside(File config) {
    try {
      return PubspecVersion.read(ConfigLocator.rootFor(config));
    } on Object catch (_) {
      return null;
    }
  }

  void _reportSdk() {
    if (argResults?.option('target') != null) {
      return;
    }

    final SdkLocator locator = _sdkLocator ?? SdkLocator();
    final SdkReport report = SdkReport.of(
      sdk: locator.locate(),
      home: locator.home,
    );

    stdout.writeln('sdk');
    for (final ProjectNote note in report.notes) {
      stdout.writeln('  ${note.line}');
    }
    stdout.writeln();
  }

  /// O `dovetail` do PATH contra este processo. Um binario instalado
  /// envelhece em silencio (o semver nao anda); o sinal que sobrava era um
  /// comando nao existir, na hora de usa-lo. Aqui a comparacao e por commit e
  /// por conjunto de comandos — `runner.commands` e o que ESTE processo sabe,
  /// e `--help` do outro e o que ele sabe.
  void _reportBinary() {
    if (argResults?.option('target') != null) {
      return;
    }

    // Os comandos que ESTE processo anuncia — os mesmos que o `--help` do
    // outro lista. `runner.commands` inclui o `help` oculto, que o usage nao
    // imprime; compara-lo daria "1 fewer command: help" contra todo binario.
    final BinaryReport report = const BinaryProbe().report(
      thisVersion: DovetailVersion.line,
      thisCommands: <String>{
        for (final Command<int> command
            in runner?.commands.values ?? const <Command<int>>[])
          if (!command.hidden) command.name,
      },
    );

    stdout.writeln('binary');
    for (final ProjectNote note in report.notes) {
      stdout.writeln('  ${note.line}');
    }
    stdout.writeln();
  }

  void _reportApp() {
    if (argResults?.option('target') != null) {
      return;
    }

    final SdkLocator locator = _sdkLocator ?? SdkLocator();
    final File? config = ConfigLocator.findFile();
    final String root = config == null
        ? Directory.current.path
        : ConfigLocator.rootFor(config);

    final AppReport report = AppReport.of(root: root, home: locator.home);

    stdout.writeln('app');
    for (final ProjectNote note in report.notes) {
      stdout.writeln('  ${note.line}');
    }
    stdout.writeln();
  }

  void _reportSpm() {
    if (argResults?.option('target') != null) {
      return;
    }

    final SdkLocator locator = _sdkLocator ?? SdkLocator();
    final SpmReport report = SpmReport.of(
      sdk: locator.locate(),
      home: locator.home,
    );

    stdout.writeln('spm');
    for (final ProjectNote note in report.notes) {
      stdout.writeln('  ${note.line}');
    }
    stdout.writeln();
  }

  /// O `--check-updates`: pergunta ao canal qual é o `latest` e compara com o
  /// SDK instalado. É opt-in e exige rede, então uma falha de rede vira nota
  /// `off`, nunca um crash — o doctor é uma sonda, e o exit code continua o do
  /// projeto, não o da rede.
  Future<void> _reportUpdateCheck() async {
    if (argResults?.flag('check-updates') != true) {
      return;
    }
    if (argResults?.option('target') != null) {
      return;
    }

    final SdkLocator locator = _sdkLocator ?? SdkLocator();
    final String? installedVersion = locator.locate()?.version;

    String? latest;
    String? failure;
    try {
      final String baseUrl = SdkChannel.baseUrlOf(
        argResults?.option('base-url'),
      );
      final SdkChannel channel = SdkChannel(
        baseUrl: baseUrl,
        // Quinze segundos, como o probe: o doctor e uma sonda, e uma sonda
        // que fica muda contra um canal morto nao esta sondando nada.
        fetcher:
            _fetcher ??
            HttpArtifactFetcher(timeout: const Duration(seconds: 15)),
      );
      latest = await channel.latest();
    } on UsageException catch (error) {
      failure = error.message;
    } on Object catch (error) {
      failure = error.toString();
    }

    stdout.writeln('updates');
    if (failure != null) {
      stdout.writeln('  off      check  $failure');
    } else {
      stdout.writeln(
        '  ok       check  ${verdict(installed: installedVersion, latest: latest)}',
      );
    }
    stdout.writeln();
  }

  /// O veredito do `--check-updates`, isolado para teste: dado o instalado e o
  /// `latest` do canal, devolve a linha que o doctor imprime. Não conhece rede
  /// nem disco — só a regra de comparação.
  static String verdict({required String? installed, required String? latest}) {
    if (latest == null) {
      return installed == null
          ? 'no SDK installed; the channel has no release yet'
          : 'the channel has no release yet (installed $installed)';
    }
    if (installed == null) {
      return 'no SDK installed; latest is $latest';
    }
    if (installed == latest) {
      return 'up to date ($latest)';
    }
    if (newerVersion(installed, latest) == latest) {
      return 'update available: $installed → $latest (dovetail self-update)';
    }
    return 'installed $installed is ahead of channel latest $latest';
  }

  int _outcomeOf(List<ToolReport> reports) {
    final bool anyUnusable = reports.any(
      (ToolReport report) => report.status == ToolStatus.unusable,
    );
    if (anyUnusable) {
      stdout
        ..writeln()
        ..writeln(
          'a tool that is present but refuses a trivial input is worse than an '
          'absent one, because a build will report success it did not earn.',
        );
      return 1;
    }
    return reports.any((ToolReport report) => !report.isUsable) ? 2 : 0;
  }

  List<TargetKey> _requested() {
    final String? target = argResults?.option('target');
    final String? arch = argResults?.option('arch');

    if (target != null) {
      return <TargetKey>[
        TargetKey(
          platformKey: arch == null ? target : '$target/$arch',
          os: target,
          arch: arch == null ? null : TargetArch.parse(arch),
        ),
      ];
    }

    final DovetailConfig? config = ConfigLocator.load();
    if (config == null || config.targets.isEmpty) {
      return <TargetKey>[
        TargetKey(
          platformKey: hostTarget(),
          os: hostTarget(),
          arch: arch == null ? null : TargetArch.parse(arch),
        ),
      ];
    }

    return config.targets.map(TargetKey.parse).toList();
  }
}
