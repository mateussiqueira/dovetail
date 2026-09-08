import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:dovetail_cli/src/dovetail_version.dart';

/// O canal de release do SDK:
///
/// ```text
/// <base>/latest                                            → "0.2.0"
/// <base>/<versão>/dovetail-sdk-<versão>-<os>-<arch>.tar.gz
/// <base>/<versão>/dovetail-sdk-<versão>-<os>-<arch>.tar.gz.sha256
/// <base>/<versão>/dovetail-sdk-<versão>-<os>-<arch>.tar.gz.minisig
/// ```
///
/// O nome do tarball é o que o `tool/build_sdk.sh` escreve, e o os/arch é o
/// do próprio binário — um self-install de binário macos-arm64 pede o SDK
/// macos-arm64, nunca outro.
final class SdkChannel {
  SdkChannel({
    required this.baseUrl,
    required this.fetcher,
    MinisignPublicKey? releaseKey,
  }) : releaseKey = releaseKey ?? _embeddedReleaseKey();

  /// A variável que carrega a base do canal quando a flag não foi dada.
  static const String installUrlEnv = 'DOVETAIL_INSTALL_URL';

  final String baseUrl;
  final ArtifactFetcher fetcher;

  /// A chave que assina o tarball. O canal é TLS, mas o tarball é assinado:
  /// um espelho comprometido não consegue forjar um artefato sem a privada
  /// (que nunca sai da máquina de release). Nula só num binário de dev, que
  /// não embute a pública — aí o download cai para o sha256.
  final MinisignPublicKey? releaseKey;

  static MinisignPublicKey? _embeddedReleaseKey() {
    const String base64 = DovetailVersion.sdkReleaseKeyBase64;
    if (base64.isEmpty) {
      return null;
    }
    return MinisignPublicKey.parse(
      'untrusted comment: dovetail sdk release key\n$base64\n',
    );
  }

  String get _root => baseUrl.replaceFirst(RegExp(r'/+$'), '');

  /// A base do canal: `--base-url` sobrepõe o ambiente, e sem os dois a
  /// recusa nomeia os dois — um instalador que adivinha o host instala o
  /// que o host decidir, não o que o usuário escolheu.
  static String baseUrlOf(String? flag) {
    final String? base = (flag != null && flag.trim().isNotEmpty)
        ? flag
        : Platform.environment[installUrlEnv];
    if (base == null || base.trim().isEmpty) {
      throw UsageException(
        'no release channel given.',
        'Pass --base-url, or set $installUrlEnv to the channel root — the '
            'host that serves latest/ and the SDK tarballs.',
      );
    }
    return base.trim();
  }

  static String tarballName(String version) =>
      'dovetail-sdk-$version-${DovetailVersion.targetOs}-'
      '${DovetailVersion.targetArch}.tar.gz';

  Uri tarballUrl(String version) =>
      Uri.parse('$_root/$version/${tarballName(version)}');

  Uri shaUrl(String version) =>
      Uri.parse('$_root/$version/${tarballName(version)}.sha256');

  Uri sigUrl(String version) =>
      Uri.parse('$_root/$version/${tarballName(version)}.minisig');

  /// O `latest` publicado, sem espaços; null quando o canal ainda não tem
  /// release (204 ou corpo vazio) — um self-update sem nada a baixar não é
  /// erro, é "já está na última".
  Future<String?> latest() async {
    final FetchedBody body = await fetcher.fetch(Uri.parse('$_root/latest'));
    if (body.isNoContent) {
      return null;
    }
    if (!body.isSuccess) {
      throw UpdateFailure(
        'the channel answered ${body.statusCode} for $_root/latest.',
        remedy: 'Check the base URL — every other endpoint hangs off it.',
      );
    }
    final String text = utf8.decode(body.bytes).trim();
    return text.isEmpty ? null : text;
  }

  /// Baixa o tarball de [version] para [target], conferido contra o
  /// `.sha256` que o canal publica antes de um byte tocar o disco.
  ///
  /// O sha256 é a camada que o instalador tem além do TLS: um espelho que
  /// serve o arquivo errado com o hash certo é detectado aqui, e um tarball
  /// que falha o hash nunca é desempacotado.
  Future<void> download(String version, File target) async {
    final FetchedBody body = await fetcher.fetch(tarballUrl(version));
    if (!body.isSuccess) {
      throw UpdateFailure(
        'the channel answered ${body.statusCode} for ${tarballUrl(version)}.',
        remedy: 'Check the base URL and that $version was actually published.',
      );
    }

    final FetchedBody sum = await fetcher.fetch(shaUrl(version));
    if (!sum.isSuccess) {
      throw UpdateFailure(
        'the channel answered ${sum.statusCode} for ${shaUrl(version)}.',
        remedy:
            'The .sha256 is part of the release; a channel that does not '
            'publish it is not installable.',
      );
    }

    final String expected = utf8.decode(sum.bytes).trim();
    final String actual = sha256.convert(body.bytes).toString();
    if (expected != actual) {
      throw const UpdateFailure(
        'the sha256 of the downloaded tarball does not match the channel.',
        remedy:
            'Retry — if it persists, the release served by the channel '
            'is broken and must not be unpacked.',
      );
    }

    // A camada que o sha256 não dá: a assinatura. Um espelho comprometido
    // pode trocar o tarball E o sha256 juntos; sem a privada ele não forja a
    // assinatura. Só quando o binário embute a pública (release de verdade).
    final MinisignPublicKey? key = releaseKey;
    if (key != null) {
      final FetchedBody sig = await fetcher.fetch(sigUrl(version));
      if (!sig.isSuccess) {
        throw UpdateFailure(
          'the channel answered ${sig.statusCode} for ${sigUrl(version)}.',
          remedy:
              'The .minisig is part of the release; a channel that does '
              'not publish it is not installable.',
        );
      }
      MinisignVerifier.verify(
        payload: body.bytes,
        signature: MinisignSignature.parse(utf8.decode(sig.bytes)),
        publicKey: key,
      );
    }

    target.writeAsBytesSync(body.bytes);
  }
}
