import 'dart:io';

import 'package:dovetail_cli/src/doctor/project_report.dart';
import 'package:dovetail_cli/src/sdk/sdk_overrides.dart';
import 'package:path/path.dart' as p;

/// O que o doctor sabe do `pubspec_overrides.yaml` do app — o triangulo se
/// fecha: o projeto declara, o SDK está instalado, e o app aponta para uma
/// versão que existe. `ok`/`off`, nunca `missing`: dentro do monorepo o
/// runtime resolve por path, e o override é o que `init --sdk` escreve — a
/// discordância se conserta com `dovetail upgrade`, não é um build quebrado.
final class AppReport {
  const AppReport(this.notes);

  final List<ProjectNote> notes;

  static final RegExp _versionPattern = RegExp(r'sdk/([^/]+)/packages');

  static AppReport of({required String root, required String home}) {
    final File overrides = File(p.join(root, SdkOverrides.fileName));
    if (!overrides.existsSync()) {
      return AppReport(<ProjectNote>[
        ProjectNote(
          subject: 'overrides',
          finding: ProjectFinding.notConfigured,
          detail:
              'none at ${overrides.path} — dovetail init --sdk, or dovetail '
              'upgrade',
        ),
      ]);
    }

    final String? version = _readVersion(overrides);
    if (version == null) {
      return AppReport(<ProjectNote>[
        ProjectNote(
          subject: 'overrides',
          finding: ProjectFinding.notConfigured,
          detail:
              '${overrides.path} points at no sdk/<version>/packages — '
              'dovetail init --sdk, or dovetail upgrade',
        ),
      ]);
    }

    final bool installed = Directory(
      p.join(home, 'sdk', version, 'packages'),
    ).existsSync();

    if (!installed) {
      return AppReport(<ProjectNote>[
        ProjectNote(
          subject: 'overrides',
          finding: ProjectFinding.notConfigured,
          detail: '$version is not installed — dovetail upgrade',
        ),
      ]);
    }

    return AppReport(<ProjectNote>[
      ProjectNote(
        subject: 'overrides',
        finding: ProjectFinding.ready,
        detail: version,
      ),
    ]);
  }

  static String? _readVersion(File overrides) =>
      _versionPattern.firstMatch(overrides.readAsStringSync())?.group(1);
}
