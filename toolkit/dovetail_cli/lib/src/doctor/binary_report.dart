import 'dart:io';

import 'package:dovetail_cli/src/doctor/project_report.dart';
import 'package:path/path.dart' as p;

/// O `dovetail` que responde no PATH, comparado com o que está rodando agora.
///
/// Um binário instalado envelhece em silêncio: o semver está parado em 0.1.0,
/// então `--version` de um binário de três semanas atrás e o da árvore de hoje
/// diziam a MESMA linha até o commit entrar nela. O sinal que sobrava era um
/// comando não existir — descoberto na hora de usá-lo. Esta seção compara os
/// dois pelo que importa: o commit de que saíram e os comandos que conhecem.
///
/// A parte pura ([BinaryReport.of], [commitOf], [commandsOf], [findOnPath])
/// não toca disco nem processo; a sonda ([BinaryProbe]) é a única que
/// executa o binário encontrado, e só pede `--version` e `--help`.
final class BinaryReport {
  const BinaryReport(this.notes);

  final List<ProjectNote> notes;

  static const String _rebuild =
      'tool/build_release.sh --install (from toolkit/dovetail_cli) rebuilds it';

  static BinaryReport of({
    required String? onPath,
    required bool isThisProcess,
    required String? onPathVersion,
    required Set<String>? onPathCommands,
    required String thisVersion,
    required Set<String> thisCommands,
  }) {
    if (onPath == null) {
      return const BinaryReport(<ProjectNote>[
        ProjectNote(
          subject: 'path',
          finding: ProjectFinding.notConfigured,
          detail:
              'no dovetail on PATH — tool/build_release.sh --install puts one '
              'at ~/.local/bin, or dovetail self-install',
        ),
      ]);
    }

    final String thisCommit = commitOf(thisVersion) ?? 'unknown';
    final String here = thisCommit == 'source'
        ? 'this checkout'
        : 'this binary ($thisCommit)';

    if (isThisProcess) {
      return BinaryReport(<ProjectNote>[
        ProjectNote(
          subject: 'path',
          finding: ProjectFinding.ready,
          detail: '$onPath  (this one, commit $thisCommit)',
        ),
      ]);
    }

    if (onPathVersion == null || onPathCommands == null) {
      return BinaryReport(<ProjectNote>[
        ProjectNote(
          subject: 'path',
          finding: ProjectFinding.notConfigured,
          detail:
              '$onPath did not answer --version and --help; whatever it is, '
              'it is not a dovetail this doctor can compare with',
        ),
      ]);
    }

    final String theirCommit = commitOf(onPathVersion) ?? 'unknown';
    final List<String> missing =
        thisCommands.difference(onPathCommands).toList()..sort();
    final List<String> extra = onPathCommands.difference(thisCommands).toList()
      ..sort();

    if (missing.isNotEmpty) {
      return BinaryReport(<ProjectNote>[
        ProjectNote(
          subject: 'path',
          finding: ProjectFinding.notConfigured,
          detail:
              '$onPath (commit $theirCommit) knows ${missing.length} fewer '
              'command${missing.length == 1 ? '' : 's'} than $here: '
              '${missing.join(', ')} — $_rebuild',
        ),
      ]);
    }

    if (extra.isNotEmpty) {
      return BinaryReport(<ProjectNote>[
        ProjectNote(
          subject: 'path',
          finding: ProjectFinding.ready,
          detail:
              '$onPath (commit $theirCommit) knows commands $here does not: '
              '${extra.join(', ')} — the binary is newer than this checkout',
        ),
      ]);
    }

    if (theirCommit == thisCommit) {
      return BinaryReport(<ProjectNote>[
        ProjectNote(
          subject: 'path',
          finding: ProjectFinding.ready,
          detail: '$onPath  (same commit, $thisCommit)',
        ),
      ]);
    }

    return BinaryReport(<ProjectNote>[
      ProjectNote(
        subject: 'path',
        finding: ProjectFinding.ready,
        detail:
            '$onPath is commit $theirCommit; $here has the same commands, so '
            'nothing is missing yet — $_rebuild',
      ),
    ]);
  }

  /// O token depois de `commit ` numa linha de `--version`. Nulo quando a
  /// linha não carrega um (um binário anterior a esse campo, ou outra coisa
  /// chamada `dovetail`).
  static String? commitOf(String versionLine) =>
      RegExp(r'commit (\S+)\)').firstMatch(versionLine)?.group(1);

  /// Os nomes debaixo de `Available commands:` num `--help` do
  /// `CommandRunner` — duas colunas, o nome indentado por dois espaços, até a
  /// linha em branco. Vazio quando o texto não tem a seção.
  static Set<String> commandsOf(String helpText) {
    final Set<String> names = <String>{};
    bool inside = false;
    for (final String line in helpText.split('\n')) {
      if (!inside) {
        inside = line.trimRight() == 'Available commands:';
        continue;
      }
      if (line.trim().isEmpty) {
        break;
      }
      final RegExpMatch? match = RegExp(r'^  (\S+)').firstMatch(line);
      if (match != null) {
        names.add(match.group(1)!);
      }
    }
    return names;
  }

  /// O primeiro `dovetail` que o PATH devolveria, na ordem em que o shell
  /// procuraria. [exists] é injetável para o teste não depender do disco.
  static String? findOnPath(
    String? pathVariable, {
    required bool Function(String path) exists,
    String? separator,
    List<String>? names,
  }) {
    if (pathVariable == null || pathVariable.isEmpty) {
      return null;
    }
    final String sep = separator ?? (Platform.isWindows ? ';' : ':');
    final List<String> candidates =
        names ??
        (Platform.isWindows
            ? const <String>['dovetail.exe', 'dovetail.bat', 'dovetail.cmd']
            : const <String>['dovetail']);
    for (final String dir in pathVariable.split(sep)) {
      if (dir.isEmpty) {
        continue;
      }
      for (final String name in candidates) {
        final String candidate = p.join(dir, name);
        if (exists(candidate)) {
          return candidate;
        }
      }
    }
    return null;
  }
}

/// A parte impura: acha o binário, resolve symlinks dos dois lados para saber
/// se é o próprio processo, e pergunta `--version` e `--help` a ele.
final class BinaryProbe {
  const BinaryProbe();

  BinaryReport report({
    required String thisVersion,
    required Set<String> thisCommands,
    Map<String, String>? environment,
  }) {
    final Map<String, String> env = environment ?? Platform.environment;
    final String? found = BinaryReport.findOnPath(
      env['PATH'],
      exists: (String path) {
        final File file = File(path);
        return file.existsSync() && _executable(file);
      },
    );
    if (found == null) {
      return BinaryReport.of(
        onPath: null,
        isThisProcess: false,
        onPathVersion: null,
        onPathCommands: null,
        thisVersion: thisVersion,
        thisCommands: thisCommands,
      );
    }

    final bool isThis =
        _resolved(found) == _resolved(Platform.resolvedExecutable);
    if (isThis) {
      return BinaryReport.of(
        onPath: found,
        isThisProcess: true,
        onPathVersion: thisVersion,
        onPathCommands: thisCommands,
        thisVersion: thisVersion,
        thisCommands: thisCommands,
      );
    }

    final String? version = _ask(found, '--version');
    final String? help = _ask(found, '--help');
    return BinaryReport.of(
      onPath: found,
      isThisProcess: false,
      onPathVersion: version?.trim(),
      onPathCommands: help == null ? null : BinaryReport.commandsOf(help),
      thisVersion: thisVersion,
      thisCommands: thisCommands,
    );
  }

  static bool _executable(File file) {
    if (Platform.isWindows) {
      return true;
    }
    // modeString() e `rwxr-xr-x`: o x do dono e o indice 2.
    return file.statSync().modeString()[2] == 'x';
  }

  static String _resolved(String path) {
    try {
      return File(path).resolveSymbolicLinksSync();
    } on FileSystemException {
      return path;
    }
  }

  /// A saída de `<binary> <flag>`, ou nulo quando ele não respondeu com exit 0
  /// — o que inclui não ser executável, morrer, ou ser outra coisa.
  static String? _ask(String binary, String flag) {
    try {
      final ProcessResult ran = Process.runSync(binary, <String>[flag]);
      if (ran.exitCode != 0) {
        return null;
      }
      return ran.stdout as String;
    } on ProcessException {
      return null;
    }
  }
}
