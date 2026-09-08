import 'dart:io';

import 'package:dovetail_cli/src/bridge/bridge_template.dart';
import 'package:dovetail_cli/src/scaffold/template_renderer.dart';

/// Copia o template renderizado: placeholders substituídos no conteúdo E nos
/// nomes de arquivo — `lib/{{name}}.dart` vira `lib/<nome>.dart`.
final class BridgeScaffold {
  const BridgeScaffold({required this.template});

  final BridgeTemplate template;

  /// Gera o plugin em [out] para o pacote [name], o crate do produto
  /// [coreCrateName] em [corePath]. Devolve os arquivos escritos, ordenados.
  List<String> render({
    required String out,
    required String name,
    required String coreCrateName,
    required String corePath,
  }) {
    final Map<String, String> values = <String, String>{
      'name': name,
      'camel_name': _camel(name),
      'core_crate_name': coreCrateName,
      'core_path': corePath,
      'rust_core_dart_path': template.rustCoreDart,
      'rust_core_rust_path': template.rustCoreRust,
    };

    return TemplateRenderer.renderTree(
      from: Directory(template.root),
      to: Directory(out),
      values: values,
    );
  }

  static String _camel(String name) => name
      .split('_')
      .map(
        (String part) => part.substring(0, 1).toUpperCase() + part.substring(1),
      )
      .join();
}
