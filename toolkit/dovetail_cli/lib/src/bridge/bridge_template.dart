import 'dart:io';

import 'package:dovetail_cli/src/sdk/sdk_locator.dart';
import 'package:path/path.dart' as p;

/// Onde o template do bridge mora, e o dovetail_rust_core que casa com ele.
///
/// Template e runtime têm que vir do mesmo lugar: o template do SDK gera um
/// package cujo dovetail_rust_core é o do SDK, e o template do repo — o dev que
/// escreve o template sem instalar o SDK a cada tentativa — gera contra o
/// repo. Um gerado que aponta para um dovetail_rust_core e resolve outro é o
/// "funciona na minha máquina" mais caro deste stack.
final class BridgeTemplate {
  const BridgeTemplate({
    required this.root,
    required this.rustCoreDart,
    required this.rustCoreRust,
  });

  final String root;
  final String rustCoreDart;
  final String rustCoreRust;

  /// O `--template` explícito vence; depois o SDK instalado; depois o repo,
  /// subindo do cwd até achar `tool/sdk/templates/bridge`. Sem nenhum, null
  /// — quem chama nomeia as alternativas.
  static BridgeTemplate? locate({String? explicit, String? sdkHome}) {
    if (explicit != null) {
      final String root = p.normalize(p.absolute(explicit));
      return Directory(root).existsSync() ? _fromRoot(root) : null;
    }

    final SdkInstall? sdk = SdkLocator(home: sdkHome).locate();
    if (sdk != null) {
      final String root = p.normalize(
        p.join(sdk.packagesDir, '..', 'templates', 'bridge'),
      );
      if (Directory(root).existsSync()) {
        return BridgeTemplate(
          root: root,
          rustCoreDart: p.join(sdk.packagesDir, 'dovetail_rust_core'),
          rustCoreRust: p.join(sdk.packagesDir, 'dovetail_rust_core', 'rust'),
        );
      }
    }

    return _fromRepo();
  }

  static BridgeTemplate _fromRoot(String root) {
    final String rustCore = p.normalize(
      p.join(root, '..', '..', '..', 'packages', 'dovetail_rust_core'),
    );
    return BridgeTemplate(
      root: root,
      rustCoreDart: rustCore,
      rustCoreRust: p.join(rustCore, 'rust'),
    );
  }

  static BridgeTemplate? _fromRepo() {
    Directory dir = Directory.current;
    while (true) {
      final String root = p.join(
        dir.path,
        'tool',
        'sdk',
        'templates',
        'bridge',
      );
      final String rustCore = p.join(dir.path, 'toolkit', 'dovetail_rust_core');
      if (Directory(root).existsSync() && Directory(rustCore).existsSync()) {
        return BridgeTemplate(
          root: root,
          rustCoreDart: rustCore,
          rustCoreRust: p.join(rustCore, 'rust'),
        );
      }
      final String parent = p.dirname(dir.path);
      if (parent == dir.path) {
        return null;
      }
      dir = Directory(parent);
    }
  }
}
