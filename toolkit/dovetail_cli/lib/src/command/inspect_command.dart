import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_cli/src/inspect/artifact_inspection.dart';
import 'package:dovetail_cli/src/inspect/artifact_inspector.dart';

final class InspectCommand extends Command<int> {
  @override
  String get name => 'inspect';

  @override
  String get description =>
      'Reports what a built artefact actually is, not what its name claims.';

  @override
  String get invocation => 'dovetail inspect <artefact> [<artefact>...]';

  @override
  Future<int> run() async {
    final List<String> paths = argResults!.rest;
    if (paths.isEmpty) {
      throw UsageException('give it at least one artefact to read.', usage);
    }

    // Existir vem antes de qualquer leitura.
    //
    // Sem isto o comando lia o KIND do nome do arquivo e saia 0 sobre um
    // caminho vazio: `inspect /nao/existe/app.dmg` respondia
    // `kind diskImage`, exit 0. So `.app` falhava, e por acidente — e o unico
    // formato que o inspetor abre de verdade.
    //
    // A promessa deste comando e "o que o arquivo e, nao o que o nome diz", e
    // num arquivo ausente ele dizia exatamente o que o nome diz. Um
    // `dovetail inspect dist/*.dmg && upload` escrito da forma obvia passava
    // quando o passo de bundle nao produziu nada — que e a falha que o
    // comando existe para pegar.
    for (final String path in paths) {
      if (!File(path).existsSync() && !Directory(path).existsSync()) {
        throw UsageException('no artefact at $path', usage);
      }
    }

    int disagreements = 0;
    for (final String path in paths) {
      final ArtifactInspection inspection = const ArtifactInspector().inspect(
        path,
      );
      inspection.lines.forEach(stdout.writeln);
      stdout.writeln();
      if (!inspection.nameAgreesWithContent) {
        disagreements++;
      }
    }

    if (disagreements > 0) {
      stdout.writeln(
        'an artefact whose name disagrees with its content is worse than one '
        'that fails to build: it ships.',
      );
      return 1;
    }
    return 0;
  }
}
