import 'package:dovetail_signer/dovetail_signer.dart';
import 'package:dovetail_cli/src/config/dovetail_config.dart';
import 'package:dovetail_cli/src/config/macos_signing_config.dart';

enum ProjectFinding { ready, missing, notConfigured }

final class ProjectNote {
  const ProjectNote({
    required this.subject,
    required this.finding,
    required this.detail,
  });

  final String subject;
  final ProjectFinding finding;
  final String detail;

  String get line => switch (finding) {
    ProjectFinding.ready => 'ok       $subject  $detail',
    ProjectFinding.notConfigured => 'off      $subject  $detail',
    ProjectFinding.missing => 'missing  $subject  $detail',
  };
}

final class ProjectReport {
  const ProjectReport(this.notes);

  final List<ProjectNote> notes;

  bool get shipCanRelease =>
      notes.every((ProjectNote note) => note.finding != ProjectFinding.missing);

  static ProjectReport of({
    required DovetailConfig? config,
    required String? version,
    required String host,
    Map<String, String>? environment,
  }) {
    if (config == null) {
      return const ProjectReport(<ProjectNote>[
        ProjectNote(
          subject: 'dovetail.yaml',
          finding: ProjectFinding.missing,
          detail: 'not here or in any parent directory; run dovetail init',
        ),
      ]);
    }

    return ProjectReport(<ProjectNote>[
      ProjectNote(
        subject: 'identifier',
        finding: ProjectFinding.ready,
        detail: config.identifier,
      ),
      ProjectNote(
        subject: 'name',
        finding: ProjectFinding.ready,
        detail: '${config.name} by ${config.manufacturer}',
      ),
      if (version == null)
        const ProjectNote(
          subject: 'version',
          finding: ProjectFinding.missing,
          detail: 'pubspec.yaml declares none, and ship reads it from there',
        )
      else
        ProjectNote(
          subject: 'version',
          finding: ProjectFinding.ready,
          detail: '$version  (from pubspec)',
        ),
      _targetsNote(config, host),
      _updateNote(config),
      _signingNote(config, host, environment),
      _serviceNote(config),
    ]);
  }

  static ProjectNote _targetsNote(DovetailConfig config, String host) {
    final Iterable<String> mine = config.targets.where(
      (String key) => _hostFor(key.split('-').first) == host,
    );
    if (mine.isEmpty) {
      return ProjectNote(
        subject: 'targets',
        finding: ProjectFinding.notConfigured,
        detail:
            '${config.targets.join(', ')} — none for $host, so ship does '
            'nothing here',
      );
    }
    return ProjectNote(
      subject: 'targets',
      finding: ProjectFinding.ready,
      detail: '${mine.join(', ')} on this host of ${config.targets.length}',
    );
  }

  static ProjectNote _updateNote(DovetailConfig config) {
    if (config.update == null) {
      return const ProjectNote(
        subject: 'update',
        finding: ProjectFinding.notConfigured,
        detail: 'no manifest is written, so installed clients learn nothing',
      );
    }
    if (config.update!.baseUrl == null) {
      return ProjectNote(
        subject: 'update',
        finding: ProjectFinding.notConfigured,
        detail:
            '${config.update!.keyPath} — no base-url, so every artefact needs '
            'its url spelled out',
      );
    }
    // O ship recusa sem a publica, entao o doctor nao pode dizer `ok` para
    // o mesmo yaml — dizia, e os dois discordavam sobre o que pode publicar.
    if (config.update!.publicKey == null) {
      return const ProjectNote(
        subject: 'update',
        finding: ProjectFinding.missing,
        detail:
            'update.public-key is not declared, so ship refuses at the '
            'release step. Declare the key the shipped app carries '
            '(dovetail keygen prints the line)',
      );
    }
    return ProjectNote(
      subject: 'update',
      finding: ProjectFinding.ready,
      detail: '${config.update!.baseUrl} signed with ${config.update!.keyPath}',
    );
  }

  static ProjectNote _signingNote(
    DovetailConfig config,
    String host,
    Map<String, String>? environment,
  ) => switch (host) {
    'macos' when config.macos == null => const ProjectNote(
      subject: 'signing',
      finding: ProjectFinding.notConfigured,
      detail: 'no sign.macos, so the build ships unsigned',
    ),
    // O ship recusa `notarize: true` sem identidade ou sem credenciais de
    // notarizacao ANTES do build; o doctor nao pode dizer `ok` para o mesmo
    // yaml no mesmo ambiente.
    'macos'
        when config.macos!.notarize &&
            environment != null &&
            _notarisationGap(config.macos!, environment) != null =>
      ProjectNote(
        subject: 'signing',
        finding: ProjectFinding.missing,
        detail: _notarisationGap(config.macos!, environment)!,
      ),
    'macos' => ProjectNote(
      subject: 'signing',
      finding: ProjectFinding.ready,
      detail:
          '${config.macos!.identityEnv}'
          '${config.macos!.notarize ? ', notarised' : ', not notarised'}',
    ),
    'windows' when config.windows == null => const ProjectNote(
      subject: 'signing',
      finding: ProjectFinding.notConfigured,
      detail: 'no sign.windows, so the installer ships unsigned',
    ),
    'windows' => ProjectNote(
      subject: 'signing',
      finding: ProjectFinding.ready,
      detail: config.windows!.certificateEnv,
    ),
    _ => const ProjectNote(
      subject: 'signing',
      finding: ProjectFinding.ready,
      detail: 'linux ships checksums, which need no identity',
    ),
  };

  static String? _notarisationGap(
    MacosSigningConfig macos,
    Map<String, String> environment,
  ) {
    bool isSet(String? value) => value != null && value.trim().isNotEmpty;
    if (!isSet(environment['APPLE_SIGNING_IDENTITY']) &&
        !isSet(environment[macos.identityEnv])) {
      return 'notarize: true, and neither ${macos.identityEnv} nor '
          'APPLE_SIGNING_IDENTITY is exported — ship refuses at the sign step';
    }
    try {
      if (NotarytoolArguments.forWhicheverIsConfigured(environment) == null) {
        return 'notarize: true, and no notarisation credential group is '
            'complete (APPLE_ID + APPLE_PASSWORD + APPLE_TEAM_ID, or '
            'APPLE_API_KEY_ID + APPLE_API_ISSUER + APPLE_API_KEY_PATH) — ship '
            'refuses at the dmg step';
      }
    } on SigningFailure catch (failure) {
      return failure.message;
    }
    return null;
  }

  static ProjectNote _serviceNote(DovetailConfig config) =>
      config.service == null
      ? const ProjectNote(
          subject: 'service',
          finding: ProjectFinding.notConfigured,
          detail: 'no privileged helper is installed by the linux packages',
        )
      : ProjectNote(
          subject: 'service',
          finding: ProjectFinding.ready,
          detail: config.service!.unit.fileName,
        );

  static String _hostFor(String os) => os == 'darwin' ? 'macos' : os;
}
