import 'dart:io';

import 'package:path/path.dart' as p;

/// O diário de diagnóstico do binário.
///
/// Um binário compilado não tem canal para reportar uma falha inesperada de
/// volta para quem o distribui: o `on Object catch` de `bin/dovetail.dart`
/// escreve no stderr e some. Este log grava a falha num arquivo rotativo para
/// o suporte — uma entrada por falha, com carimbo de tempo, o tipo do erro, a
/// mensagem e as primeiras linhas do stack.
///
/// É melhor esforço: `record` nunca lança e nunca bloqueia o caminho
/// principal de falha, que continua sendo o stderr.
final class CliLog {
  CliLog({
    String? home,
    this.maxBytes = _defaultMaxBytes,
    this.maxStackLines = _defaultMaxStackLines,
  }) : home = home ?? Platform.environment['DOVETAIL_HOME'] ?? _defaultHome();

  /// A raiz onde o log mora. Espelha a regra do `SdkLocator`: `$DOVETAIL_HOME`
  /// e, na falta, `~/.dovetail`.
  final String home;

  /// Teto em bytes. Quando a próxima entrada ultrapassaria o teto, o arquivo
  /// roda para `.old` e uma nova entrada começa um arquivo limpo.
  final int maxBytes;

  /// Quantas linhas do stack entram numa entrada.
  final int maxStackLines;

  static const int _defaultMaxBytes = 5 * 1024 * 1024;
  static const int _defaultMaxStackLines = 40;

  /// Marca a quebra de linha original dentro da linha única do log.
  static const String _newlineMark = '\u23CE';

  static String _defaultHome() =>
      p.join(Platform.environment['HOME'] ?? '.', '.dovetail');

  /// O caminho do arquivo: `<home>/log/dovetail.log`.
  String get path => p.join(home, 'log', 'dovetail.log');

  /// Grava uma falha, sem nunca lançar.
  void record({
    required String runtimeType,
    required String message,
    StackTrace? stack,
  }) {
    try {
      final String entry = '${_entry(runtimeType, message, stack)}\n';
      final File file = File(path);
      final Directory directory = file.parent;
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
      if (file.existsSync() && file.lengthSync() + entry.length > maxBytes) {
        _rotate(file);
      }
      file.writeAsStringSync(entry, mode: FileMode.append, flush: true);
    } catch (_) {
      // Melhor esforço: o stderr já reportou; o log não pode atrapalhar.
    }
  }

  void _rotate(File file) {
    final File previous = File('${file.path}.old');
    if (previous.existsSync()) {
      previous.deleteSync();
    }
    file.renameSync('${file.path}.old');
  }

  String _entry(String runtimeType, String message, StackTrace? stack) {
    final StringBuffer buffer = StringBuffer()
      ..write(_timestamp())
      ..write(' ')
      ..write(runtimeType)
      ..write(': ')
      ..write(_singleLine(message));
    for (final String frame in _frames(stack)) {
      buffer
        ..write(' | ')
        ..write(frame);
    }
    return buffer.toString();
  }

  List<String> _frames(StackTrace? stack) {
    if (stack == null) {
      return const <String>[];
    }
    final List<String> lines = stack
        .toString()
        .trim()
        .split('\n')
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList();
    return lines.take(maxStackLines).toList();
  }

  String _singleLine(String text) =>
      text.replaceAll('\r', '').replaceAll('\n', _newlineMark);

  String _timestamp() => DateTime.now().toUtc().toIso8601String();
}
