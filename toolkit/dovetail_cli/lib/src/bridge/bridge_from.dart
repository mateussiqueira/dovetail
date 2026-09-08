import 'dart:io';

import 'package:path/path.dart' as p;

/// Replica as entradas de produto de um bridge existente (`--from`) no
/// recém-gerado: o `rust/src/api/`, o `rust/src/support.rs` tipado, e os
/// crates irmãos que o template não declara.
///
/// O template entrega a mecânica, não o conteúdo — `rust/src/api/` sai vazio,
/// `support.rs` é genérico (erro como String) e os crates irmãos do produto
/// não estão declarados. Quem migra do fixture tinha que copiar isso à mão,
/// exatamente o que o `tool/ci/prove_bridge.sh` faz. O `--from` é essa cópia
/// como flag.
final class BridgeFrom {
  const BridgeFrom();

  /// Copia as entradas de produto de [from] (um bridge já gerado) para o
  /// bridge gerado em [out], que fala com o crate [coreCrateName]. Devolve os
  /// caminhos escritos (copiados ou com dependências acrescentadas), ordenados.
  List<String> copy({
    required String from,
    required String out,
    required String coreCrateName,
  }) {
    final List<String> written = <String>[];
    final String fromRustSrc = p.join(from, 'rust', 'src');

    final Directory api = Directory(p.join(fromRustSrc, 'api'));
    if (api.existsSync()) {
      _copyDirectory(
        api,
        Directory(p.join(out, 'rust', 'src', 'api')),
        written,
      );
    }

    final File support = File(p.join(fromRustSrc, 'support.rs'));
    if (support.existsSync()) {
      final String target = p.join(out, 'rust', 'src', 'support.rs');
      File(target).writeAsStringSync(support.readAsStringSync());
      written.add(target);
    }

    final List<String> extraDeps = _extraDeps(
      File(p.join(from, 'rust', 'Cargo.toml')),
      coreCrateName,
    );
    if (extraDeps.isNotEmpty) {
      final String cargoPath = p.join(out, 'rust', 'Cargo.toml');
      _appendDeps(File(cargoPath), extraDeps);
      written.add(cargoPath);
    }

    return written..sort();
  }

  static void _copyDirectory(
    Directory from,
    Directory to,
    List<String> written,
  ) {
    to.createSync(recursive: true);
    for (final FileSystemEntity entity in from.listSync()) {
      if (entity is Directory) {
        _copyDirectory(
          entity,
          Directory(p.join(to.path, p.basename(entity.path))),
          written,
        );
      } else if (entity is File) {
        final File target = File(p.join(to.path, p.basename(entity.path)));
        target.writeAsStringSync(entity.readAsStringSync());
        written.add(target.path);
      }
    }
  }

  /// As linhas `name = { path = ... }` do `[dependencies]` que o template não
  /// declarou: tudo que aponta por caminho e não é o core, o `dovetail_rust_core` nem
  /// o `flutter_rust_bridge` — os crates irmãos do produto.
  static List<String> _extraDeps(File cargo, String coreCrateName) {
    if (!cargo.existsSync()) {
      return <String>[];
    }
    final RegExp dep = RegExp(
      r'^([A-Za-z_][A-Za-z0-9_-]*)\s*=\s*\{[^}]*path\s*=',
      multiLine: true,
    );
    final List<String> result = <String>[];
    for (final RegExpMatch match in dep.allMatches(cargo.readAsStringSync())) {
      final String name = match.group(1)!;
      if (name == coreCrateName ||
          name == 'dovetail_rust_core' ||
          name == 'flutter_rust_bridge') {
        continue;
      }
      result.add(match.group(0)!);
    }
    return result;
  }

  static void _appendDeps(File cargo, List<String> extraDeps) {
    final List<String> lines = cargo.readAsLinesSync();
    final int header = lines.indexWhere(
      (String line) => line.trim() == '[dependencies]',
    );
    final int insertAt = header < 0 ? lines.length : header + 1;
    final List<String> updated = <String>[
      ...lines.take(insertAt),
      ...extraDeps,
      ...lines.skip(insertAt),
    ];
    cargo.writeAsStringSync('${updated.join('\n')}\n');
  }
}
