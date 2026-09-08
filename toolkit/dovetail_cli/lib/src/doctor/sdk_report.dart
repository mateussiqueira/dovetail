import 'package:dovetail_cli/src/doctor/project_report.dart';
import 'package:dovetail_cli/src/dovetail_version.dart';
import 'package:dovetail_cli/src/sdk/sdk_locator.dart';
import 'package:dovetail_cli/src/sdk/version_order.dart';

/// O que o doctor sabe do SDK instalado, no mesmo formato de nota do
/// project — `ok`/`off`, nunca `missing`: o SDK é opcional dentro do
/// monorepo (o runtime resolve por path), e obrigatório é o que o aceite
/// do container prova, não o que o doctor de um dev bloqueia.
final class SdkReport {
  const SdkReport(this.notes);

  final List<ProjectNote> notes;

  static SdkReport of({required SdkInstall? sdk, required String home}) {
    if (sdk == null) {
      return SdkReport(<ProjectNote>[
        ProjectNote(
          subject: 'install',
          finding: ProjectFinding.notConfigured,
          detail:
              'nothing at $home/sdk — curl -fsSL "\$DOVETAIL_INSTALL_URL"/install.sh | sh, or '
              'dovetail self-install --base-url <url>',
        ),
      ]);
    }

    final bool matches = sdk.version == DovetailVersion.number;
    return SdkReport(<ProjectNote>[
      ProjectNote(
        subject: 'version',
        finding: ProjectFinding.ready,
        detail: matches
            ? sdk.version
            : '${sdk.version}  (binary ${DovetailVersion.number})',
      ),
      if (!matches)
        ProjectNote(
          subject: 'sync',
          finding: ProjectFinding.notConfigured,
          detail:
              newerVersion(sdk.version, DovetailVersion.number) == sdk.version
              ? 'the SDK is ahead of the binary — dovetail self-update'
              : 'the binary is ahead of the SDK — dovetail self-install',
        ),
    ]);
  }
}
