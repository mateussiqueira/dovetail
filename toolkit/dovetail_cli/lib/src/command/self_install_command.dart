import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:path/path.dart' as p;

import 'package:dovetail_cli/src/dovetail_version.dart';
import 'package:dovetail_cli/src/sdk/sdk_channel.dart';
import 'package:dovetail_cli/src/sdk/sdk_installer.dart';
import 'package:dovetail_cli/src/sdk/sdk_locator.dart';

/// Instala o runtime do SDK ao lado deste binário, da versão que ele é.
///
/// O `tool/sdk/install.sh` é o caminho curl|sh; este comando é o mesmo
/// trabalho de dentro do binário, para quem já tem o binário em mãos e não
/// quer o segundo download por fora. Os dois falam o mesmo canal.
final class SelfInstallCommand extends Command<int> {
  SelfInstallCommand({this._sdkLocator, this._fetcher, this._binDir}) {
    argParser.addOption(
      'base-url',
      help: 'the release channel root; defaults to ${SdkChannel.installUrlEnv}',
    );
  }

  final SdkLocator? _sdkLocator;
  final ArtifactFetcher? _fetcher;
  final String? _binDir;

  @override
  String get name => 'self-install';

  @override
  String get description =>
      'Installs the dovetail runtime beside this binary, from a release '
      'channel.';

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

    const String version = DovetailVersion.number;
    final Directory stage = Directory.systemTemp.createTempSync('dovetail-sdk');
    final File tarball = File(
      p.join(stage.path, SdkChannel.tarballName(version)),
    );

    try {
      stdout.writeln('downloading ${channel.tarballUrl(version)}');
      await channel.download(version, tarball);

      final SdkInstaller installer = SdkInstaller(
        home: locator.home,
        binDir: _binDir,
      );
      await installer.extract(tarball);
      final Link link = installer.linkBin();

      stdout
        ..writeln('installed dovetail $version at ${locator.home}')
        ..writeln('  ${link.path} → ${link.targetSync()}')
        ..writeln(
          '  sdk/$version/packages carries the runtime the app imports',
        );
      return 0;
    } finally {
      stage.deleteSync(recursive: true);
    }
  }
}
