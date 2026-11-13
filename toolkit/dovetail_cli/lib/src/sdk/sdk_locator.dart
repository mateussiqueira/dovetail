import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:dovetail_cli/src/dovetail_version.dart';
import 'package:dovetail_cli/src/sdk/version_order.dart';

/// A installação local do SDK: `$DOVETAIL_HOME/sdk/<versão>/packages`.
///
/// É o que o instalador desempacota (docs/instalador.md, Fase 3) e o que o
/// `init --sdk` aponta no `pubspec_overrides.yaml` do app. Os pacotes são os
/// diretórios em `packages/` — a lista não é duplicada aqui de propósito: o
/// SDK instalado é a fonte de verdade, e o barrel_test é quem prende o barril.
final class SdkInstall {
  const SdkInstall({required this.version, required this.packagesDir});

  final String version;
  final String packagesDir;

  /// Os pacotes do runtime presentes no SDK, pelo nome do diretório.
  ///
  /// Só conta o diretório que traz `pubspec.yaml`: a pasta do SDK é a fonte
  /// de verdade, e um diretório solto viraria um override que o pub recusa.
  List<String> packages() =>
      Directory(packagesDir)
          .listSync()
          .whereType<Directory>()
          .map((Directory d) => p.basename(d.path))
          .where(
            (String name) =>
                File(p.join(packagesDir, name, 'pubspec.yaml')).existsSync(),
          )
          .toList()
        ..sort();
}

/// Procura o SDK instalado. Sem [home], usa `$DOVETAIL_HOME` e, na falta,
/// `~/.dovetail`.
///
/// A versão preferida é a do próprio binário — o comando que fala é o
/// binário, e a versão que ele recomenda é a dele. Quando ela não está
/// instalada, a mais recente serve (um binário novo falando com um SDK
/// um pouco mais velho ainda resolve o runtime); quando nada está
/// instalado, devolve null e quem chama nomeia o comando que instala.
final class SdkLocator {
  SdkLocator({
    String? home,
    p.Context? context,
    Map<String, String>? environment,
  }) : _context = context ?? p.context,
       home =
           home ??
           _defaultHome(
             context ?? p.context,
             environment ?? Platform.environment,
           );

  final String home;
  final p.Context _context;

  static String _defaultHome(
    p.Context context,
    Map<String, String> environment,
  ) {
    final String? override = environment['DOVETAIL_HOME'];
    if (override != null) return override;
    final String? local = environment['LOCALAPPDATA'];
    if (context.style == p.Style.windows && local != null && local.isNotEmpty) {
      return context.join(local, 'dovetail');
    }
    return context.join(
      environment['HOME'] ?? environment['USERPROFILE'] ?? '.',
      '.dovetail',
    );
  }

  SdkInstall? locate() {
    final Directory sdkRoot = Directory(_context.join(home, 'sdk'));
    if (!sdkRoot.existsSync()) {
      return null;
    }

    final List<String> versions =
        sdkRoot
            .listSync()
            .whereType<Directory>()
            .map((Directory d) => _context.basename(d.path))
            .where(
              (String name) => Directory(
                _context.join(sdkRoot.path, name, 'packages'),
              ).existsSync(),
            )
            .toList()
          ..sort();

    if (versions.isEmpty) {
      return null;
    }

    final String version = versions.contains(DovetailVersion.number)
        ? DovetailVersion.number
        : versions.reduce(newerVersion);

    return SdkInstall(
      version: version,
      packagesDir: _context.join(sdkRoot.path, version, 'packages'),
    );
  }
}
