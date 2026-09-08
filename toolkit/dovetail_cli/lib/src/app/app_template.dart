import 'dart:io';

import 'package:dovetail_cli/src/sdk/sdk_locator.dart';
import 'package:path/path.dart' as p;

/// Onde o template do app mora — o que o `dovetail new` escreve: a árvore
/// clean-arch em Dart, o crate Rust do núcleo, as duas suites de checks e o
/// overlay que completa o bridge.
final class AppTemplate {
  const AppTemplate({required this.root});

  final String root;

  /// O `--template` explícito vence; depois o SDK instalado; depois o repo,
  /// subindo do cwd até achar `tool/sdk/templates/app`. Sem nenhum, null —
  /// quem chama nomeia as alternativas.
  static String? locate({String? explicit, String? sdkHome}) {
    if (explicit != null) {
      final String root = p.normalize(p.absolute(explicit));
      return Directory(root).existsSync() ? root : null;
    }

    final SdkInstall? sdk = SdkLocator(home: sdkHome).locate();
    if (sdk != null) {
      final String root = p.normalize(
        p.join(sdk.packagesDir, '..', 'templates', 'app'),
      );
      if (Directory(root).existsSync()) {
        return root;
      }
    }

    Directory dir = Directory.current;
    while (true) {
      final String root = p.join(dir.path, 'tool', 'sdk', 'templates', 'app');
      if (Directory(root).existsSync()) {
        return root;
      }
      final String parent = p.dirname(dir.path);
      if (parent == dir.path) {
        return null;
      }
      dir = Directory(parent);
    }
  }
}
