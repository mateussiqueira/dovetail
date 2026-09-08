import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:path/path.dart' as p;

import 'package:dovetail_cli/src/dovetail_version.dart';
import 'package:dovetail_cli/src/sdk/sdk_channel.dart';
import 'package:dovetail_cli/src/sdk/sdk_installer.dart';
import 'package:dovetail_cli/src/sdk/sdk_locator.dart';
import 'package:dovetail_cli/src/sdk/version_order.dart';

/// Troca o SDK para o `latest` do canal, mantendo a versão que os apps
/// apontam. O aceite da fase é exatamente isso: `sdk/<antiga>` fica no
/// disco, só `sdk/<nova>` entra e o binário é trocado.
final class SelfUpdateCommand extends Command<int> {
  SelfUpdateCommand({this._sdkLocator, this._fetcher, this._binDir}) {
    argParser.addOption(
      'base-url',
      help: 'the release channel root; defaults to ${SdkChannel.installUrlEnv}',
    );
  }

  final SdkLocator? _sdkLocator;
  final ArtifactFetcher? _fetcher;
  final String? _binDir;

  @override
  String get name => 'self-update';

  @override
  String get description =>
      'Updates the SDK to the latest release, keeping the version apps '
      'already point at.';

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

    if (newerVersion(latest, binaryVersion) == binaryVersion) {
      stdout.writeln(
        latest == binaryVersion
            ? 'already current ($binaryVersion)'
            : 'channel latest ($latest) is older than this binary '
                  '($binaryVersion) — nothing to do',
      );
      return 0;
    }

    final Directory stage = Directory.systemTemp.createTempSync('dovetail-sdk');
    final File tarball = File(
      p.join(stage.path, SdkChannel.tarballName(latest)),
    );

    try {
      stdout.writeln('downloading ${channel.tarballUrl(latest)}');
      await channel.download(latest, tarball);

      final SdkInstaller installer = SdkInstaller(
        home: locator.home,
        binDir: _binDir,
      );
      await installer.extract(tarball);
      installer.linkBin();

      stdout
        ..writeln('updated $binaryVersion → $latest')
        ..writeln(
          '  sdk/$binaryVersion kept — apps pointing at it keep '
          'resolving',
        )
        ..writeln('  sdk/$latest installed at ${locator.home}')
        ..writeln(
          '  note: this process keeps the old binary in memory; '
          'the next invocation is the new one',
        );
      return 0;
    } finally {
      stage.deleteSync(recursive: true);
    }
  }
}
