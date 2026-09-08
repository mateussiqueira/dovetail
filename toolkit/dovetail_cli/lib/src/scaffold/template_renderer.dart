import 'dart:io';

import 'package:path/path.dart' as p;

/// Renders a template directory into a destination, replacing `{{chave}}`
/// placeholders no conteúdo E nos nomes de arquivo — `lib/{{name}}.dart`
/// vira `lib/<nome>.dart`. Usado pelo scaffold do bridge e pelo do app.
final class TemplateRenderer {
  const TemplateRenderer();

  /// Copia [from] para [to] com os placeholders de [values] substituídos.
  /// Devolve os arquivos escritos, ordenados.
  static List<String> renderTree({
    required Directory from,
    required Directory to,
    required Map<String, String> values,
  }) {
    final List<String> written = <String>[];
    _walk(from, to, values, written);
    return written..sort();
  }

  static void _walk(
    Directory from,
    Directory to,
    Map<String, String> values,
    List<String> written,
  ) {
    to.createSync(recursive: true);
    for (final FileSystemEntity entity in from.listSync()) {
      final String renderedBase = _render(p.basename(entity.path), values);
      final String targetPath = p.join(to.path, renderedBase);
      if (entity is Directory) {
        _walk(entity, Directory(targetPath), values, written);
      } else if (entity is File) {
        File(
          targetPath,
        ).writeAsStringSync(_render(entity.readAsStringSync(), values));
        _keepExecutable(entity, targetPath);
        written.add(targetPath);
      }
    }
  }

  /// O bit de execução do template, preservado na cópia.
  ///
  /// `writeAsStringSync` cria o arquivo com o modo padrão do processo, e o
  /// modo da ORIGEM se perde. O efeito no projeto gerado era total: os 35
  /// `.sh` e os dois hooks saíam `rw-r--r--`, então `./run_app.sh` morria com
  /// `Permission denied` (exit 126) e — pior, porque é silencioso — o git
  /// **ignorava os hooks**, dizendo apenas `hint: The '.githooks/pre-commit'
  /// hook was ignored because it's not set as executable`. Um commit com
  /// arquivo desformatado passava limpo.
  ///
  /// O projeto que o `dovetail new` entrega existe em boa parte para trazer
  /// esse portão pronto, e ele nunca rodou uma vez na casa de ninguém.
  ///
  /// Windows não tem o conceito, e `Process.runSync('chmod')` ali só gastaria
  /// um processo para falhar — daí a guarda.
  static void _keepExecutable(File source, String targetPath) {
    if (Platform.isWindows) {
      return;
    }
    // `modeString()` devolve NOVE caracteres — `rwxr-xr-x` —, sem o caractere
    // de tipo que o `ls -l` põe na frente. O `x` do dono é o índice 2; ler o 3
    // (o do grupo, por analogia com o `ls`) faz a checagem passar em arquivo
    // errado e falhar no certo. Basta o do dono: um template executável para o
    // dono é um script, e é o dono que roda.
    final String mode = source.statSync().modeString();
    if (mode.length < 3 || mode[2] != 'x') {
      return;
    }
    Process.runSync('chmod', <String>['+x', targetPath]);
  }

  static String _render(String source, Map<String, String> values) {
    String rendered = source;
    for (final MapEntry<String, String> entry in values.entries) {
      rendered = rendered.replaceAll('{{${entry.key}}}', entry.value);
    }
    return rendered;
  }
}
