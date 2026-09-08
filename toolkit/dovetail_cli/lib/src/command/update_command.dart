import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:path/path.dart' as p;

import 'package:dovetail_cli/src/config/pubspec_version.dart';
import 'package:dovetail_cli/src/dovetail_version.dart';
import 'package:dovetail_cli/src/sdk/sdk_channel.dart';
import 'package:dovetail_cli/src/sdk/sdk_installer.dart';
import 'package:dovetail_cli/src/sdk/sdk_locator.dart';
import 'package:dovetail_cli/src/sdk/sdk_overrides.dart';
import 'package:dovetail_cli/src/sdk/version_order.dart';

/// O ciclo de versão do consumidor num comando só: `self-update` (troca o SDK
/// para o latest do canal) seguido de `upgrade` (re-aponta o
/// `pubspec_overrides.yaml` do app). Com `--root`, faz os dois; sem, só o SDK
/// muda e o app fica para um `upgrade` posterior.
final class UpdateCommand extends Command<int> {
  UpdateCommand({this._sdkLocator, this._fetcher, this._binDir}) {
    argParser
      ..addOption(
        'base-url',
        help:
            'the release channel root; defaults to ${SdkChannel.installUrlEnv}',
      )
      ..addOption(
        'root',
        help:
            'the app directory to re-point; when omitted, only the SDK is '
            'updated and the app is left for `upgrade`',
      );
  }

  final SdkLocator? _sdkLocator;
  final ArtifactFetcher? _fetcher;
  final String? _binDir;

  @override
  String get name => 'update';

  @override
  String get description =>
      'Updates the SDK to the channel latest and re-points the app overrides, '
      'in one step.';

  @override
  Future<int> run() async {
    final String baseUrl = SdkChannel.baseUrlOf(argResults?.option('base-url'));
    final SdkLocator locator = _sdkLocator ?? SdkLocator();
    final SdkChannel channel = SdkChannel(
      baseUrl: baseUrl,
      // Trinta segundos entre dois pedacos, nao para o download inteiro: um
      // tarball de SDK num link lento nao tem prazo total razoavel, mas um
      // host que parou de responder nao pode deixar o comando mudo.
      fetcher:
          _fetcher ?? HttpArtifactFetcher(timeout: const Duration(seconds: 30)),
    );

    const String binaryVersion = DovetailVersion.number;
    final String? latest = await channel.latest();
    if (latest == null) {
      stdout.writeln('the channel has no release yet — nothing to do');
      return 0;
    }

    bool installed = false;
    if (newerVersion(latest, binaryVersion) == binaryVersion) {
      stdout.writeln(
        latest == binaryVersion
            ? 'already current ($binaryVersion)'
            : 'channel latest ($latest) is older than this binary '
                  '($binaryVersion) — nothing to do',
      );
    } else {
      await _install(locator, channel, binaryVersion, latest);
      installed = true;
    }

    final String? root = argResults?.option('root');
    if (root == null || root.trim().isEmpty) {
      if (installed) {
        stdout.writeln(
          '  note: no --root given, so no app was re-pointed — run '
          '`dovetail upgrade` to re-point one',
        );
      }
      return 0;
    }

    final SdkInstall sdk = installed
        ? SdkInstall(
            version: latest,
            packagesDir: p.join(locator.home, 'sdk', latest, 'packages'),
          )
        : _requireSdk(locator);
    return _repoint(root.trim(), sdk);
  }

  /// O mesmo trabalho do `self-update`: baixa e instala [to] ao lado da
  /// versão atual, trocando o binário. É a mesma maquinaria
  /// (`SdkChannel`/`SdkInstaller`), não uma cópia da lógica — o download já
  /// vem conferido contra o `.sha256` e a assinatura antes de tocar o disco.
  Future<void> _install(
    SdkLocator locator,
    SdkChannel channel,
    String from,
    String to,
  ) async {
    final Directory stage = Directory.systemTemp.createTempSync('dovetail-sdk');
    final File tarball = File(p.join(stage.path, SdkChannel.tarballName(to)));

    try {
      stdout.writeln('downloading ${channel.tarballUrl(to)}');
      await channel.download(to, tarball);

      final SdkInstaller installer = SdkInstaller(
        home: locator.home,
        binDir: _binDir,
      );
      await installer.extract(tarball);
      installer.linkBin();

      stdout
        ..writeln('updated $from → $to')
        ..writeln('  sdk/$from kept — apps pointing at it keep resolving')
        ..writeln('  sdk/$to installed at ${locator.home}');
    } finally {
      stage.deleteSync(recursive: true);
    }
  }

  /// O mesmo trabalho do `upgrade`: escreve o `pubspec_overrides.yaml` do app
  /// apontando para [sdk]. Sem `pubspec.yaml` ele pula com um aviso, em vez
  /// de quebrar — o override pertence a um projeto, e sem projeto não há o
  /// que re-apontar.
  int _repoint(String root, SdkInstall sdk) {
    if (!File(p.join(root, PubspecVersion.fileName)).existsSync()) {
      stdout.writeln(
        'no ${PubspecVersion.fileName} in $root — skipped re-pointing the app',
      );
      return 0;
    }

    final File target = File(p.join(root, SdkOverrides.fileName));
    final String oldVersion = _readVersion(target);
    target.writeAsStringSync(SdkOverrides.render(sdk));

    stdout
      ..writeln('wrote ${target.path}')
      ..writeln('  the runtime resolves from the SDK at ${sdk.packagesDir}');
    if (oldVersion != 'none' && oldVersion != sdk.version) {
      stdout.writeln('  $oldVersion → ${sdk.version}');
    }
    return 0;
  }

  /// Exige um SDK instalado para onde o app possa apontar, nomeando o
  /// `self-install` — o comando que põe o runtime no disco quando o canal não
  /// tem nada mais novo a instalar.
  SdkInstall _requireSdk(SdkLocator locator) {
    final SdkInstall? sdk = locator.locate();
    if (sdk == null) {
      throw UsageException(
        'no dovetail SDK installed at ${locator.home}/sdk — `dovetail '
            'self-install` installs it.',
        'There is nothing to point ${SdkOverrides.fileName} at.\n\n$usage',
      );
    }
    return sdk;
  }

  static final RegExp _versionPattern = RegExp(r'sdk/([^/]+)/packages');

  /// A versão a que o override atual aponta, lida do primeiro
  /// `sdk/<versão>/packages` no arquivo — 'none' quando o arquivo não existe
  /// ou não aponta para SDK nenhum.
  String _readVersion(File target) {
    if (!target.existsSync()) {
      return 'none';
    }
    final Match? match = _versionPattern.firstMatch(target.readAsStringSync());
    return match?.group(1) ?? 'none';
  }
}
