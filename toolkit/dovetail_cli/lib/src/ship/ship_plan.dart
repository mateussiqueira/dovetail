import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:dovetail_signer/dovetail_signer.dart';
import 'package:dovetail_cli/src/build/flutter_build.dart';
import 'package:dovetail_cli/src/config/darwin_service_route.dart';
import 'package:dovetail_cli/src/config/macos_service_config.dart';
import 'package:dovetail_cli/src/config/macos_signing_config.dart';
import 'package:dovetail_cli/src/config/config_failure.dart';
import 'package:dovetail_cli/src/config/dovetail_config.dart';
import 'package:dovetail_cli/src/ship/ship_channel.dart';
import 'package:dovetail_cli/src/ship/ship_step.dart';
import 'package:dovetail_cli/src/ship/upgrade_code.dart';
import 'package:path/path.dart' as p;

final class ShipPlan {
  const ShipPlan({
    required this.steps,
    required this.artifacts,
    this.downloads = const <String, String>{},
    this.refusals = const <String>[],
    this.notices = const <String>[],
  });

  final List<ShipStep> steps;

  /// O que entra no manifesto, por chave de plataforma: o arquivo que o
  /// UPDATER baixa e instala. No macOS e o `.app.tar.gz`, nao o dmg.
  ///
  /// O canal interno nao escreve manifesto nenhum, entao para ele isto fica
  /// vazio e o instalador sai em [downloads].
  final Map<String, String> artifacts;

  /// O que NAO entra no manifesto e ainda assim e um artefato do release: o
  /// `.dmg`, para a primeira instalacao pela mao do usuario, e — no canal
  /// interno — o instalador inteiro, que nao tem manifesto para entrar.
  final Map<String, String> downloads;

  /// O que vai recusar mais tarde, sabido agora.
  ///
  /// A esteira gasta minutos antes de chegar ao `release`: um
  /// `flutter build --release`, o `codesign` sobre o bundle e o `hdiutil`.
  /// Descobrir no ultimo passo uma condicao que o `dovetail.yaml` respondia em
  /// milissegundos joga tudo isso fora — e o `--dry-run`, cuja ajuda diz
  /// "imprime os passos e nao roda nenhum", saia 0 sobre um plano que nao
  /// completa.
  ///
  /// Isto apareceu ao tornar `update.public-key` obrigatoria no `release`: a
  /// guarda passou a disparar, e o planejador nao sabia dela. Toda checagem
  /// que o ultimo passo faz e que o plano ja pode fazer pertence aqui.
  final List<String> refusals;

  /// O que o ship deixa dito sem impedir nada: hoje, o arquivo que o canal
  /// interno produz e o que o testador faz com ele. Um aviso que nao muda o
  /// plano mora aqui, e nao em [refusals], que sai 1.
  final List<String> notices;

  static const String outputDirectory = 'dist';

  static ShipPlan of({
    required DovetailConfig config,
    required String version,
    required String host,
    required String binary,
    bool build = true,
    String? windowsFormat,
    Map<String, String>? environment,
    ShipChannel channel = ShipChannel.release,
  }) {
    final bool internal = channel.isInternal;

    // O canal interno e um build de DEBUG: o testador precisa de simbolo e
    // log para dizer o que falhou. Todo o resto do plano — o diretorio de
    // saida, o `--app-dir` que o bundle recebe, o bundle que o sign assina —
    // tem de seguir o mesmo modo, senao o plano empacota um diretorio Release
    // que talvez exista de um build anterior, com outro conteudo.
    final bool releaseBuild = !internal;

    final List<String> mine = _targetsForHost(config, host);
    if (mine.isEmpty) {
      throw ConfigFailure(
        'this host builds none of the declared targets.',
        remedy:
            'It is $host, and dovetail.yaml lists '
            '${config.targets.join(', ')}. That is a runner whose part of the '
            'matrix lives elsewhere, not an error — but ship has nothing to '
            'do here.',
      );
    }

    final MacosServiceConfig? macosService = config.service?.macos;

    // O formato do download no macOS sai do canal e da rota declarada. O canal
    // de release manda um dmg: ele monta uma imagem e o usuario arrasta o
    // `.app`, sem rodar script nenhum. O canal interno, quando o componente e
    // instalado por um instalador (`route: system`), manda o `.pkg` — o unico
    // formato do macOS com um postinstall como root. Sem componente declarado,
    // o interno tambem e um dmg.
    final String macosDownloadFormat =
        internal && macosService?.route == DarwinServiceRoute.system
        ? 'pkg'
        : 'dmg';

    // The release step below names the artefacts and lets the url be
    // derived, because the url is the only part of the manifest that cannot be
    // guessed from the project. Refusing here rather than at the last step
    // matters: the build is the slow half, and a plan that dies after it has
    // spent twenty minutes to tell you about one missing line.
    //
    // O canal interno nao tem passo de release, entao a guarda do manifesto
    // nao vale para ele: quem recusa o interno com `update:` e a recusa
    // explicita mais abaixo, e nao uma falta de base-url.
    if (!internal && config.update != null && config.update!.baseUrl == null) {
      throw const ConfigFailure(
        'update.base-url is not set, so the release step has nothing to point '
        'at.',
        remedy:
            'Add it to dovetail.yaml, under update:\n'
            '    base-url: https://your.cdn/releases\n'
            'The manifest url is built as <base-url>/<version>/<file>. To '
            'point each artefact somewhere of its own instead, skip ship and '
            'call: dovetail release --artifact platformKey=url=path',
      );
    }

    final List<ShipStep> steps = <ShipStep>[];
    final Map<String, String> artifacts = <String, String>{};
    final Map<String, String> downloads = <String, String>{};
    final List<String> refusals = <String>[];
    final List<String> notices = <String>[];

    if (build) {
      steps.add(
        ShipStep(
          label: 'build $host',
          command: 'build',
          arguments: <String>[
            '--target',
            host,
            if (!releaseBuild) '--no-release',
          ],
        ),
      );
    }

    for (final List<String> group in _groups(mine, host)) {
      final List<String> arches = group
          .map((String key) => bundlerArch(key.split('-').last))
          .toList();
      final String artifact = p.join(
        outputDirectory,
        artifactNameFor(
          host: host,
          binary: binary,
          version: version,
          arches: arches,
          windowsFormat: windowsFormat,
          identifier: config.identifier,
          name: config.name,
          manufacturer: config.manufacturer,
          macosFormat: macosDownloadFormat,
          release: releaseBuild,
        ),
      );
      final String label = group.length == 1
          ? group.single
          : '${group.first.split('-').first}-universal';

      if (host == 'macos') {
        // O manifesto aponta para o que o updater instala; o pkg (ou o dmg,
        // sem componente) e download. O canal interno nao tem manifesto, entao
        // la so existe o download.
        downloads[label] = artifact;
        if (!internal) {
          artifacts[label] = p.join(
            outputDirectory,
            artifactNameFor(
              host: host,
              binary: binary,
              version: version,
              arches: arches,
              windowsFormat: windowsFormat,
              identifier: config.identifier,
              name: config.name,
              manufacturer: config.manufacturer,
              macosFormat: 'tar',
              release: releaseBuild,
            ),
          );
        }
      } else if (internal) {
        // Sem manifesto, o instalador do canal interno nao e uma entrada de
        // release; ele e so o arquivo que o testador recebe.
        downloads[label] = artifact;
      } else {
        artifacts[label] = artifact;
      }

      final ShipStep bundling = ShipStep(
        label: 'bundle $label',
        command: 'bundle',
        arguments: _bundleArguments(
          config: config,
          version: version,
          host: host,
          binary: binary,
          arches: arches,
          windowsFormat: windowsFormat,
          macosFormat: macosDownloadFormat,
          release: releaseBuild,
        ),
      );
      final ShipStep signing = ShipStep(
        label: 'sign $label',
        command: 'sign',
        arguments: <String>[
          '--target',
          host,
          if (host == 'macos') ...<String>[
            '--bundle',
            builtBundleFor(binary, release: releaseBuild),
          ] else ...<String>['--file', artifact],
          if (host == 'linux') ...<String>['--out-dir', outputDirectory],
          if (host == 'macos' &&
              config.macos?.entitlements != null) ...<String>[
            '--entitlements',
            config.macos!.entitlements!,
          ],
          // `notarize: true` e declarar release de verdade: um ship que
          // terminasse VERDE com um .app sem assinatura porque a variavel da
          // identidade nao estava exportada e o pior dos dois mundos, porque
          // parece certo. Com notarize false — o que `init` escreve — o
          // build local sem Developer ID segue sem assinar e diz isso, como a
          // doc promete. O `.app` e notarizado ANTES de virar dmg, para o
          // ticket ficar grampeado nele tambem: quem arrasta o app da imagem
          // para /Applications abre um app com ticket, mesmo offline.
          if (host == 'macos' && !internal &&
              (config.macos?.notarize ?? false)) ...<String>[
            '--require-signature',
            '--notarize',
          ],
          // O canal interno assina ad-hoc: sem Developer ID e sem
          // notarizacao. O `.app` ainda tem de ser assinado — um bundle sem
          // assinatura nenhuma nao abre no macOS moderno —, mas com a
          // identidade `-`, que e a unica disponivel antes de a equipe ter um
          // certificado.
          if (host == 'macos' && internal) '--ad-hoc',
        ],
      );

      // No Windows sao DUAS assinaturas, e a ordem entre elas e o ponto.
      //
      // O payload primeiro, porque o instalador embrulha os binarios: assinar
      // so o instalador produz um arquivo que passa pelo SmartScreen e entao
      // deposita executaveis sem assinatura no disco de quem instalou. Isso e
      // pior que nao assinar nada, porque parece certo.
      //
      // O macOS tambem sao duas, e a razao e outra. O selo do `.app` cobre o
      // CONTEUDO, entao assinar o bundle antes de embrulhar assina tudo o que
      // vai dentro — isso estava certo. O que faltava e que o `.dmg` e ele
      // proprio um artefato que o Gatekeeper avalia quando o usuario monta a
      // imagem: sem uma assinatura depois do bundle, o arquivo que a pessoa
      // baixa chega sem assinar mesmo com um Developer ID configurado, e a
      // notarizacao — que e do dmg, nao do app — nunca tinha o que grampear.
      //
      // Era `[signing, bundling]`, sem terceiro passo: o `.app` saia assinado
      // dentro de um contentor que nao estava.
      //
      // E o Linux nao assina binario nenhum — o que sai de la e um SHA256SUMS.
      final ShipStep signingPayload = ShipStep(
        label: 'sign payload $label',
        command: 'sign',
        arguments: <String>[
          '--target',
          host,
          '--directory',
          FlutterBuild.outputOf(host, release: releaseBuild),
        ],
      );

      // O contentor macOS: assina o `.dmg` depois de montado, e e aqui que a
      // notarizacao acontece. Notarizar o `.app` solto e possivel mas nao e o
      // que o usuario baixa; o que precisa de ticket grampeado e a imagem.
      //
      // Um `.pkg` nao entra neste passo: quem assina um pkg e o `productsign`,
      // com um certificado Developer ID Installer — outra identidade, que este
      // passo nao tem. `codesign` sobre ele nao assina nada do que o Gatekeeper
      // avalia.
      //
      // O canal interno tambem nao passa aqui: um dmg ad-hoc nao compra nada
      // (o testador instala por instrucao, nao por Gatekeeper) e um pkg nao e
      // assinavel pelas ferramentas daqui.
      final ShipStep signingContainer = ShipStep(
        label: 'sign dmg $label',
        command: 'sign',
        arguments: <String>[
          '--target',
          host,
          '--file',
          artifact,
          if (config.macos?.notarize ?? false) ...<String>[
            '--require-signature',
            '--notarize',
          ],
        ],
      );

      // O arquivo do updater: o `.app` ja assinado, em tar.gz, depois de o dmg
      // estar assinado e (se for o caso) notarizado — o conteudo e o mesmo, e
      // o `.app` nao muda mais depois do seu proprio passo de assinatura.
      //
      // So existe no canal de release: sem manifesto, o `.app.tar.gz` nao tem
      // quem o leia.
      final ShipStep archiving = ShipStep(
        label: 'archive $label',
        command: 'bundle',
        arguments: <String>[
          ..._bundleArguments(
            config: config,
            version: version,
            host: host,
            binary: binary,
            arches: arches,
            windowsFormat: windowsFormat,
            macosFormat: 'tar',
            release: releaseBuild,
          ),
        ],
      );

      steps.addAll(switch (host) {
        // Os dois sao notarizados: o .app primeiro (e o que abre), o dmg
        // depois (e o que se baixa e o Gatekeeper avalia ao montar). O
        // archive vem por ultimo: e o mesmo .app, ja selado. Com um pkg nao ha
        // segundo: o .app ja foi assinado, e o pacote que o carrega nao e
        // assinavel pelas ferramentas daqui. O canal interno para no bundle:
        // nao ha manifesto, entao nao ha archive nem release.
        'macos' => internal
            ? <ShipStep>[signing, bundling]
            : <ShipStep>[
                signing,
                bundling,
                if (macosDownloadFormat == 'dmg') signingContainer,
                archiving,
              ],
        'windows' => <ShipStep>[signingPayload, bundling, signing],
        _ => <ShipStep>[bundling, signing],
      });
    }

    // O canal interno nao escreve manifesto nenhum, e a combinacao com uma
    // secao `update:` e recusada em vez de ignorada: um artefato interno nao
    // pode aparecer no canal de atualizacao que quem ja instalou le, e deixar
    // isso para a disciplina de quem roda o comando e deixar a porta aberta.
    if (internal && config.update != null) {
      refusals.add(
        'the internal channel writes no updater manifest, and dovetail.yaml '
        'declares an update section. An internal artefact must not reach the '
        'update channel installed clients read, so ship refuses the '
        'combination rather than trusting whoever runs it. Drop the update '
        'section for an internal build, or use --channel release.',
      );
    }

    // O canal falha honesto: declarar um componente que o canal escolhido nao
    // consegue instalar para antes do build, com a razao, em vez de entregar
    // um arquivo do qual o daemon nunca sai.
    if (host == 'macos' && macosService != null) {
      if (!internal && macosService.route == DarwinServiceRoute.system) {
        refusals.add(
          'service.macos.route is system, and the release channel ships a '
          '.dmg: a dmg mounts an image and the user drags the .app out, so it '
          'runs no script and the daemon "${macosService.label}" never '
          'installs. Use --channel internal, whose .pkg runs the postinstall '
          'that puts the daemon in /Library and boots it, or move the daemon '
          'to route: bundled for a release from the .dmg.',
        );
      }
      if (internal && macosService.route == DarwinServiceRoute.bundled) {
        refusals.add(
          'service.macos.route is bundled, and the internal channel signs '
          'ad-hoc: SMAppService registers the daemon by a valid signature with '
          'the same Team ID as the app, and an ad-hoc build has no Team ID. '
          'The daemon would install and never register. Use --channel release '
          'with a Developer ID, or declare route: system for an internal '
          'build, whose installer loads the daemon with launchctl instead.',
        );
      }
    }

    if (!internal &&
        config.update != null &&
        config.update!.publicKey == null) {
      refusals.add(
        'update.public-key is not declared, and the plan ends in a release '
        'step that refuses without it. Declare the public key the shipped app '
        'carries in dovetail.yaml — everything before the release would be '
        'built and then thrown away.',
      );
    }

    final bool notarising = config.macos?.notarize ?? false;
    if (!internal && notarising && host == 'macos') {
      refusals.addAll(_notarisationRefusals(config.macos!, environment));
    }

    // Uma linha, e a de sempre: o que o testador faz com o arquivo que vai
    // receber. Assinar um pkg exige um Developer ID Installer, que o canal
    // interno nunca usa — dizer isso e mais honesto do que fingir Gatekeeper.
    // So num plano que nao recusa: um plano que nao vai rodar nao instrui
    // ninguem a instalar.
    if (host == 'macos' &&
        macosDownloadFormat == 'pkg' &&
        refusals.isEmpty) {
      notices.add(
        'unsigned pkg: install it with '
        '`sudo installer -pkg ${downloads.values.first} -target /` — Finder '
        'refuses a package with no Developer ID Installer signature.',
      );
    }

    // O passo de release so existe no canal de release; o interno recusa a
    // secao `update:` acima, entao aqui ele nunca chega.
    if (!internal && config.update != null) {
      steps.add(
        ShipStep(
          label: 'release $version',
          command: 'release',
          arguments: <String>[
            '--version',
            version,
            if (config.update!.unencrypted) '--unencrypted-key',
            for (final MapEntry<String, String> made
                in artifacts.entries) ...<String>[
              '--artifact',
              '${made.key}=${made.value}',
            ],
          ],
        ),
      );
    }

    return ShipPlan(
      steps: steps,
      artifacts: artifacts,
      downloads: downloads,
      refusals: refusals,
      notices: notices,
    );
  }

  /// O que o passo de assinatura vai recusar depois do build, sabido agora
  /// pelo ambiente: `notarize: true` sem identidade exportada, ou sem um
  /// grupo completo de credenciais de notarizacao. Sem ambiente (os testes
  /// puros do plano), nada a dizer.
  static List<String> _notarisationRefusals(
    MacosSigningConfig macos,
    Map<String, String>? environment,
  ) {
    if (environment == null) {
      return const <String>[];
    }
    final List<String> refusals = <String>[];
    if (!_isSet(environment['APPLE_SIGNING_IDENTITY']) &&
        !_isSet(environment[macos.identityEnv])) {
      refusals.add(
        'sign.macos.notarize is true, and neither ${macos.identityEnv} nor '
        'APPLE_SIGNING_IDENTITY is exported — the sign step would refuse '
        'after the build. Export the Developer ID identity, or set '
        'notarize: false for a local, unsigned build.',
      );
    }
    try {
      if (NotarytoolArguments.forWhicheverIsConfigured(environment) == null) {
        refusals.add(
          'sign.macos.notarize is true, and no notarisation credential group '
          'is complete: APPLE_ID + APPLE_PASSWORD + APPLE_TEAM_ID, or '
          'APPLE_API_KEY_ID + APPLE_API_ISSUER + APPLE_API_KEY_PATH. The dmg '
          'step would refuse after the build.',
        );
      }
    } on SigningFailure catch (failure) {
      refusals.add(
        '${failure.message}${failure.remedy == null ? '' : ' ${failure.remedy}'}',
      );
    }
    return refusals;
  }

  static bool _isSet(String? value) => value != null && value.trim().isNotEmpty;

  static List<String> _bundleArguments({
    required DovetailConfig config,
    required String version,
    required String host,
    required String binary,
    required List<String> arches,
    required String? windowsFormat,
    String macosFormat = 'dmg',
    bool release = true,
  }) => <String>[
    '--target',
    host,
    for (final String arch in arches) ...<String>['--arch', arch],
    '--product-name',
    config.name,
    '--manufacturer',
    config.manufacturer,
    '--identifier',
    config.identifier,
    '--version',
    version,
    '--main-binary',
    binary,
    '--app-dir',
    host == 'macos'
        ? builtBundleFor(binary, release: release)
        : FlutterBuild.outputOf(host, release: release),
    '--out-dir',
    outputDirectory,
    // Explicito quando difere do padrao do `bundle`: o passo do canal interno
    // diz `pkg`, e o de arquivo do release diz `tar`. O dmg e o padrao do
    // `bundle`, entao o release sai sem a flag, como sempre saiu.
    if (host == 'macos' && macosFormat != 'dmg') ...<String>[
      '--macos-format',
      macosFormat,
    ],
    if (host == 'windows' && windowsFormat != null) ...<String>[
      '--windows-format',
      windowsFormat,
    ],
    // O bundle recusa msi sem UpgradeCode, e o ship nunca o passava: um ship
    // Windows morria no passo de bundle. Derivado do identifier, estavel.
    if (host == 'windows' && windowsFormat == 'msi') ...<String>[
      '--upgrade-code',
      UpgradeCode.forIdentifier(config.identifier),
    ],
  ];

  static String builtBundleFor(String binary, {bool release = true}) => p.join(
    FlutterBuild.outputOf('macos', release: release),
    '$binary.app',
  );

  static String bundlerArch(String wireArch) =>
      wireArch == 'aarch64' ? 'arm64' : wireArch;

  static List<List<String>> _groups(List<String> mine, String host) =>
      host == 'macos'
      ? <List<String>>[mine]
      : mine.map((String key) => <String>[key]).toList();

  static List<String> _targetsForHost(DovetailConfig config, String host) =>
      config.targets
          .where((String key) => _hostFor(key.split('-').first) == host)
          .toList();

  static String _hostFor(String os) => os == 'darwin' ? 'macos' : os;

  static String artifactNameFor({
    required String host,
    required String binary,
    required String version,
    required List<String> arches,
    required String? windowsFormat,
    required String identifier,
    required String name,
    required String manufacturer,
    String macosFormat = 'dmg',
    bool release = true,
  }) {
    final BundleSpec spec = BundleSpec(
      productName: name,
      manufacturer: manufacturer,
      identifier: identifier,
      version: AppVersion.parse(version),
      mainBinaryName: binary,
      appDirectory: builtBundleFor(binary, release: release),
      outputDirectory: outputDirectory,
    );
    final TargetArch first = TargetArch.parse(arches.first);

    return switch (host) {
      'macos' when macosFormat == 'tar' => AppArchiveBundler(
        runner: const SystemProcessRunner(),
        requiredArchitectures: arches.map(TargetArch.parse).toSet(),
      ).fileNameFor(spec),
      'macos' when macosFormat == 'pkg' => PkgBundler(
        runner: const SystemProcessRunner(),
        requiredArchitectures: arches.map(TargetArch.parse).toSet(),
      ).fileNameFor(spec),
      'macos' => DmgBundler(
        runner: const SystemProcessRunner(),
        requiredArchitectures: arches.map(TargetArch.parse).toSet(),
      ).fileNameFor(spec),
      'linux' => DebBundler(arch: first).fileNameFor(spec),
      _ =>
        windowsFormat == 'msi'
            ? MsiSpec(
                bundle: spec,
                upgradeCode: UpgradeCode.forIdentifier(identifier),
                arch: first,
              ).msiFileName
            : spec.installerFileNameFor(first),
    };
  }
}
