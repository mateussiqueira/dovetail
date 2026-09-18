import 'dart:io';

import 'package:dovetail_signer/dovetail_signer.dart';
import 'package:dovetail_cli/src/config/darwin_service_route.dart';
import 'package:dovetail_cli/src/config/dovetail_config.dart';
import 'package:dovetail_cli/src/config/macos_service_config.dart';
import 'package:dovetail_cli/src/config/macos_signing_config.dart';
import 'package:dovetail_cli/src/config/service_config.dart';
import 'package:dovetail_cli/src/ship/ship_channel.dart';
import 'package:path/path.dart' as p;

enum ProjectFinding { ready, missing, warning, notConfigured }

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
    // Nem `ok` nem `missing`: o projeto esta coerente, e o canal escolhido nao
    // consegue instalar o que ele declara. Quem le precisa da razao, nao de um
    // veredito — e o `ship` recusa pelo mesmo motivo, entao os dois concordam.
    ProjectFinding.warning => 'warn     $subject  $detail',
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

    /// A raiz contra a qual `service.macos.binary` resolve. O `doctor` passa o
    /// diretorio do `dovetail.yaml`; nulo cai no cwd, como o relatorio do app
    /// ja faz quando nao ha arquivo, para o resultado continuar decidivel.
    String? root,

    /// O canal que o `doctor` esta perguntando. `release` e o padrao, para o
    /// relatorio continuar respondendo o que sempre respondeu; `internal`
    /// responde a mesma pergunta que o `ship --channel internal` vai fazer.
    ShipChannel channel = ShipChannel.release,
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
      ..._serviceNotes(config, root, channel),
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

  /// Uma linha por plataforma, porque a resposta e por plataforma.
  ///
  /// Enquanto havia uma linha so, ela falava de Linux: um produto que embarca
  /// daemon no macOS e nao declara unit systemd lia "nenhum helper", o que era
  /// verdade sobre o Linux e mentira sobre a maquina em que ele roda.
  ///
  /// A declaracao do daemon, sozinha, nao e prova de nada: `dovetail build`
  /// COPIA o binario e nao o compila, entao um projeto cujo daemon nunca foi
  /// construido passava aqui como `ready` e quebrava no embed. Por isso o
  /// caminho declarado em `service.macos.binary` e conferido no disco — a
  /// mesma pergunta que a secao `spm` faz ao `.xcframework`, e pelo mesmo
  /// motivo: quem esqueceu o passo so descobria no build.
  static List<ProjectNote> _serviceNotes(
    DovetailConfig config,
    String? root,
    ShipChannel channel,
  ) {
    final ServiceConfig? service = config.service;
    if (service == null) {
      return const <ProjectNote>[
        ProjectNote(
          subject: 'service',
          finding: ProjectFinding.notConfigured,
          detail: 'no privileged component is declared, on any platform',
        ),
      ];
    }

    return <ProjectNote>[
      if (service.unit == null)
        const ProjectNote(
          subject: 'service (linux)',
          finding: ProjectFinding.notConfigured,
          detail: 'the deb and the rpm install no unit',
        )
      else
        ProjectNote(
          subject: 'service (linux)',
          finding: ProjectFinding.ready,
          detail: service.unit!.fileName,
        ),
      if (service.macos == null)
        const ProjectNote(
          subject: 'service (macos)',
          finding: ProjectFinding.notConfigured,
          detail: 'no daemon travels in the bundle',
        )
      else
        _macosServiceNote(service.macos!, root, channel),
    ];
  }

  /// O daemon declarado existe onde o `service.macos.binary` diz?
  ///
  /// `missing` e nao `notConfigured`: sem o binario o embed RECUSA — o
  /// `dovetail build` para —, entao o projeto nao pode ser publicado como
  /// declarado. O detalhe nomeia o caminho declarado, que e o unico conserto
  /// que quem le tem em maos: a ferramenta nao conhece a cadeia de build de
  /// quem a usa.
  static ProjectNote _macosServiceNote(
    MacosServiceConfig daemon,
    String? root,
    ShipChannel channel,
  ) {
    final String declared = daemon.binary;
    final File binary = File(
      p.isAbsolute(declared)
          ? declared
          : p.join(root ?? Directory.current.path, declared),
    );
    if (!binary.existsSync()) {
      return ProjectNote(
        subject: 'service (macos)',
        finding: ProjectFinding.missing,
        detail:
            '$declared is not on disk, and the bundle embeds it — build the '
            'daemon before ship',
      );
    }

    // A pergunta e a do canal: o formato que ESTE canal empacota consegue
    // instalar o daemon que a configuracao declara? A resposta depende da
    // rota, e o `ship` recusa pelo mesmo motivo — se o doctor dissesse `ok`
    // aqui, os dois discordariam sobre o que pode sair.
    final bool installs = switch ((channel, daemon.route)) {
      (ShipChannel.release, DarwinServiceRoute.bundled) => true,
      (ShipChannel.internal, DarwinServiceRoute.system) => true,
      _ => false,
    };
    if (installs) {
      return ProjectNote(
        subject: 'service (macos)',
        finding: ProjectFinding.ready,
        detail:
            '${daemon.plistFileName}  (${daemon.route.name}; '
            '${channel.wire} installs it)',
      );
    }

    // `warn`, e nao `missing`: o projeto esta coerente, o outro canal o
    // entrega, e um `missing` aqui derrubaria um job de CI que esta correto.
    // O que falta e so o canal certo — e ele vai nomeado.
    return ProjectNote(
      subject: 'service (macos)',
      finding: ProjectFinding.warning,
      detail: channel == ShipChannel.release
          ? 'route: system, and the release channel ships a .dmg, which runs '
                'no script — the daemon never installs. Use --channel internal, '
                'whose .pkg installs it'
          : 'route: bundled, and the internal channel signs ad-hoc — '
                'SMAppService refuses a daemon without a valid Team ID. Use '
                '--channel release with a Developer ID, or route: system',
    );
  }

  static String _hostFor(String os) => os == 'darwin' ? 'macos' : os;
}
