import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:dovetail_signer/dovetail_signer.dart';
import 'package:dovetail_cli/src/command/doctor_command.dart';
import 'package:dovetail_cli/src/config/config_failure.dart';
import 'package:dovetail_cli/src/config/config_locator.dart';
import 'package:dovetail_cli/src/config/darwin_service_route.dart';
import 'package:dovetail_cli/src/config/dovetail_config.dart';
import 'package:dovetail_cli/src/config/macos_service_config.dart';
import 'package:dovetail_cli/src/config/windows_signing_config.dart';
import 'package:path/path.dart' as p;

final class SignCommand extends Command<int> {
  SignCommand({this._runner, this._environment, this._root}) {
    argParser
      ..addOption('target', allowed: knownTargets, help: 'defaults to the host')
      ..addMultiOption('file', help: 'artefact to sign; repeatable')
      ..addMultiOption(
        'directory',
        help:
            'Windows only: sign every .exe and .dll under it, recursively. '
            'The payload of an installer is signed BEFORE the installer, and '
            'this is what names the payload.',
      )
      ..addOption(
        'bundle',
        help:
            'the .app to sign on macOS, inside out; on macOS --file is the '
            '.dmg it ships in, signed after it is built',
      )
      ..addOption(
        'entitlements',
        help:
            'macOS: the plist the app is signed with; defaults to the Release '
            'CODE_SIGN_ENTITLEMENTS of macos/Runner.xcodeproj, then '
            'macos/Runner/Release.entitlements, because codesign --force '
            'without it drops the entitlements the build had',
      )
      ..addOption('out-dir', defaultsTo: '.')
      ..addFlag('require-signature', negatable: false)
      ..addFlag('notarize', negatable: false)
      ..addOption('osslsigncode', defaultsTo: 'osslsigncode')
      ..addOption(
        'certificate',
        help: 'PEM certificate or PKCS#12 bundle; overrides the environment',
      )
      ..addOption('private-key', help: 'PEM key beside --certificate')
      ..addOption('timestamp-url', help: 'RFC3161 server')
      ..addOption('program-name', help: 'shown by the Windows UAC prompt')
      ..addMultiOption(
        'entitlements-for',
        help: 'relative/path/in.app=entitlements.plist ; repeatable',
      );
  }

  /// Injetaveis nos testes: quem roda `codesign`/`notarytool`, e o ambiente
  /// de onde saem as credenciais. Em producao sao o sistema e o processo.
  final ProcessRunner? _runner;
  final Map<String, String>? _environment;

  /// De onde procurar o dovetail.yaml; injetavel nos testes, o cwd em producao.
  final String? _root;

  ProcessRunner get _signingRunner => _runner ?? const SystemProcessRunner();

  /// O `notarytool --wait` leva minutos e fala enquanto espera; ao vivo.
  ProcessRunner get _liveRunner => _runner ?? SystemProcessRunner.echoing;

  @override
  String get name => 'sign';

  @override
  String get description =>
      'Signs what a bundle already produced. Never packages anything.';

  @override
  Future<int> run() async {
    final ArgResults args = argResults!;
    final String target = args.option('target') ?? hostTarget();
    final Map<String, String> environment =
        _environment ?? Platform.environment;
    final SigningPolicy policy = SigningPolicy(
      requireSignature: args.flag('require-signature'),
    );

    switch (target) {
      case 'macos':
        return _macos(args, policy, environment);
      case 'windows':
        return _windows(args, policy, environment);
      case 'linux':
        return _linux(args);
    }

    throw UsageException('unknown target $target', usage);
  }

  Future<int> _macos(
    ArgResults args,
    SigningPolicy policy,
    Map<String, String> processEnvironment,
  ) async {
    // macOS e Windows consultam o dovetail.yaml (identity-env, entitlements,
    // sign.windows.*); o Linux nunca o le. Um yaml invalido vira nota, nao
    // recusa: `sign` sempre funcionou sem o arquivo, e um projeto a meio
    // editar nao pode morrer por uma chave que este comando nunca leu.
    final ({DovetailConfig? config, String root}) project = projectContext(
      from: _root,
    );
    final Map<String, String> environment = withIdentityFromConfig(
      processEnvironment,
      project.config,
    );

    final String? bundle = args.option('bundle');
    final List<String> files = args.multiOption('file');
    if (bundle == null && files.isEmpty) {
      throw UsageException(
        'macos needs --bundle (the .app) or --file (the .dmg it ships in)',
        usage,
      );
    }
    if (bundle != null && files.isNotEmpty) {
      throw UsageException(
        'macos signs --bundle or --file in one call, not both.',
        'The .app is signed inside out, with entitlements and the hardened '
            'runtime; the .dmg is a flat file signed after it is built. They '
            'are two steps, in that order — ship runs them that way.\n\n$usage',
      );
    }
    if (bundle == null) {
      return _macosFiles(args, policy, environment, files);
    }
    _requireOnDisk(bundle, flag: '--bundle');
    final String root = project.root;

    final Map<String, String> nested = _nestedEntitlements(
      args,
      config: project.config,
      root: root,
    );

    final PolicyVerdict verdict = policy.decide(
      group: NotarizationCredentials.identity,
      environment: environment,
    );
    stdout.writeln(verdict.note);
    if (!verdict.shouldSign) {
      return 0;
    }

    // `codesign --force` sem `--entitlements` SUBSTITUI a assinatura que o
    // Xcode escreveu e deixa cair os entitlements que o build tinha
    // (app-sandbox, o que o Info.plist prometeu). Um app assinado que perdeu
    // o sandbox e outro app, diferente do que foi testado — e o ship nao
    // passava nada aqui. O padrao e o plist que o projeto Xcode assina em
    // Release; a linha abaixo diz o que foi aplicado para ninguem ter de
    // descobrir com `codesign -d --entitlements`.
    final String? given = args.option('entitlements');
    final ({String path, String source})? found = given == null
        ? defaultEntitlements(root)
        : null;
    final String? entitlements = given ?? found?.path;
    stdout.writeln(
      entitlements == null
          ? 'entitlements  none — the signature carries no entitlements'
          : given != null
          ? 'entitlements  $entitlements'
          : 'entitlements  ${p.relative(entitlements, from: root)}  '
                '(${found!.source}; --entitlements overrides)',
    );

    await MacosSigner(runner: _signingRunner).sign(
      request: MacosSigningRequest(
        bundlePath: bundle,
        identity: environment['APPLE_SIGNING_IDENTITY']!,
        appEntitlements: entitlements,
        entitlementsByRelativePath: nested,
      ),
      contents: Directory(bundle)
          .listSync(recursive: true, followLinks: false)
          .map((FileSystemEntity entity) => entity.path)
          .toList(),
    );
    stdout.writeln('signed $bundle');

    await _requireSameTeamIdAsTheApp(bundle, project.config?.service?.macos);

    if (!args.flag('notarize')) {
      return 0;
    }

    // Ao vivo: `notarytool submit --wait` leva de minutos a dezenas deles, e
    // imprime o estado enquanto espera. Bufferizado, o comando ficava mudo do
    // "signed" ate o "notarised" — indistinguivel de travado. O resultado
    // continua inteiro para o parser do id de submissao.
    final NotarizationOutcome outcome = await NotarizationStep(
      runner: _liveRunner,
    ).run(bundlePath: bundle, environment: environment);
    _reportNotarisation(
      outcome,
      bundle,
      requireSignature: args.flag('require-signature'),
    );
    return 0;
  }

  /// `--require-signature` cobre a notarizacao quando `--notarize` a pede. Sem
  /// isto, um ship com `notarize: true` e sem credenciais Apple saia 0
  /// dizendo "nothing was submitted" — verde sobre um dmg que o Gatekeeper
  /// vai recusar.
  void _reportNotarisation(
    NotarizationOutcome outcome,
    String path, {
    required bool requireSignature,
  }) {
    if (outcome == NotarizationOutcome.notarised) {
      stdout.writeln('notarised and stapled $path');
      return;
    }
    if (requireSignature) {
      throw const SigningFailure(
        'notarisation was required and no credential group is complete.',
        remedy:
            'Set APPLE_ID, APPLE_PASSWORD and APPLE_TEAM_ID, or APPLE_API_KEY_ID, '
            'APPLE_API_ISSUER and APPLE_API_KEY_PATH. --notarize with '
            '--require-signature is how ship asks for a release the Gatekeeper '
            'accepts; a dmg nobody submitted is not that.',
      );
    }
    stdout.writeln(
      'no notarisation credentials are set; nothing was submitted',
    );
  }

  /// O contentor: o `.dmg` (ou mais de um) assinado como arquivo plano, e
  /// notarizado ele mesmo. E o que o usuario baixa e o que o Gatekeeper
  /// avalia ao montar — o `.app` la dentro ja foi assinado, inside out, no
  /// passo anterior. O ship planejava este passo e o comando o recusava com
  /// "macos needs --bundle": a esteira morria no quarto de cinco passos.
  Future<int> _macosFiles(
    ArgResults args,
    SigningPolicy policy,
    Map<String, String> environment,
    List<String> files,
  ) async {
    for (final String file in files) {
      _requireOnDisk(file, flag: '--file');
      if (Directory(file).existsSync()) {
        throw UsageException(
          '--file $file is a directory.',
          'A bundle is signed with --bundle: inside out, with the hardened '
              'runtime and its entitlements. --file is for the flat .dmg; '
              'signing a .app as a flat file would replace its seal with a '
              'shallow one and print "signed" over it.\n\n$usage',
        );
      }
    }

    final PolicyVerdict verdict = policy.decide(
      group: NotarizationCredentials.identity,
      environment: environment,
    );
    stdout.writeln(verdict.note);
    if (!verdict.shouldSign) {
      return 0;
    }

    final MacosSigner signer = MacosSigner(runner: _signingRunner);
    for (final String file in files) {
      await signer.signFile(
        path: file,
        identity: environment['APPLE_SIGNING_IDENTITY']!,
      );
      stdout.writeln('signed $file');
    }

    if (!args.flag('notarize')) {
      return 0;
    }

    for (final String file in files) {
      final NotarizationOutcome outcome = await NotarizationStep(
        runner: _liveRunner,
      ).runOnFile(path: file, environment: environment);
      _reportNotarisation(
        outcome,
        file,
        requireSignature: args.flag('require-signature'),
      );
    }
    return 0;
  }

  /// O dovetail.yaml e a raiz do projeto, quando existem. Um yaml que nao
  /// parseia vira uma nota e um config nulo — `sign` nunca dependeu dele.
  static ({DovetailConfig? config, String root}) projectContext({
    String? from,
  }) {
    final File? file = ConfigLocator.findFile(from: from);
    if (file == null) {
      return (config: null, root: from ?? Directory.current.path);
    }
    final String root = ConfigLocator.rootFor(file);
    try {
      return (
        config: DovetailConfig.parse(
          file.readAsStringSync(),
          origin: file.path,
        ),
        root: root,
      );
    } on ConfigFailure catch (failure) {
      stdout.writeln(
        'note          ${file.path} could not be read '
        '(${failure.message}); sign.macos is not applied',
      );
      return (config: null, root: root);
    }
  }

  /// O plist que o build assinou, lido do projeto Xcode: o
  /// `CODE_SIGN_ENTITLEMENTS` dos blocos `XCBuildConfiguration` cujo `name` e
  /// `Release`, em macos/Runner.xcodeproj/project.pbxproj. Pela CONFIGURACAO,
  /// nao pelo nome do arquivo: o Xcode reaponta essa chave quando alguem mexe
  /// em Signing & Capabilities, e o plist de Release pode se chamar
  /// `Runner.entitlements`. Adivinhar pelo nome aplicaria um plist velho em
  /// silencio. Sem pbxproj, ou sem a chave no bloco, o nome do template fica
  /// como reserva — e e o que acontece num projeto com FLAVOR, onde as
  /// configuracoes se chamam `Release-free` e nao `Release`: ali nao ha um
  /// Release unico a adivinhar, e quem sabe qual e declara
  /// `sign.macos.entitlements`. Resolvido contra a RAIZ do projeto — a mesma de onde o yaml
  /// veio — e nao contra o cwd, que pode ser qualquer subpasta.
  static ({String path, String source})? defaultEntitlements(String root) {
    final String macos = p.join(root, 'macos');
    final File pbxproj = File(
      p.join(macos, 'Runner.xcodeproj', 'project.pbxproj'),
    );
    if (pbxproj.existsSync()) {
      final RegExp setting = RegExp(
        r'CODE_SIGN_ENTITLEMENTS\s*=\s*"?([^";]+)"?;',
      );
      // Um pedaco por bloco, e dentro dele so o que vem ANTES do proprio
      // `name` — nao uma regex atravessando o arquivo.
      //
      // Era `isa = XCBuildConfiguration;(.*?)name = (\w+);` com dotAll, e
      // `\w+` nao casa um nome ENTRE ASPAS, que e como o pbxproj escreve
      // qualquer nome com hifen — `name = "Debug-staging";`, a forma que o
      // Xcode gera para flavor. Sem casar ali, o `.*?` seguia para o bloco
      // seguinte e parava no `name = Release;` DELE: as buildSettings lidas
      // eram do bloco de Debug, e a linha impressa dizia que vinham do
      // Release. Um app de produto assinado com o plist de Debug — com
      // `allow-jit` e `network.server` — e anunciado como Release.
      for (final String block
          in pbxproj
              .readAsStringSync()
              .split('isa = XCBuildConfiguration;')
              .skip(1)) {
        final RegExpMatch? name = RegExp(
          r'name = "?([^";]+)"?;',
        ).firstMatch(block);
        if (name == null || name.group(1)!.trim() != 'Release') {
          continue;
        }
        final RegExpMatch? declared = setting.firstMatch(
          block.substring(0, name.start),
        );
        if (declared == null) {
          continue;
        }
        final String path = p.join(macos, declared.group(1)!.trim());
        if (File(path).existsSync()) {
          return (
            path: path,
            source: 'Release configuration of the Xcode project',
          );
        }
      }
    }
    final String template = p.join(macos, 'Runner', 'Release.entitlements');
    return File(template).existsSync()
        ? (path: template, source: "the Flutter template's file")
        : null;
  }

  /// `sign.macos.identity-env` dizia o nome da variavel que carrega a
  /// identidade — `init` a escrevia, o `doctor` a imprimia, a doc a explicava
  /// — e nada lia esse nome: o signer sempre leu APPLE_SIGNING_IDENTITY. Uma
  /// chave declarada e ignorada e pior que ausente, porque quem exportou a
  /// variavel que a doc mandou ve o build sair sem assinar e nao sabe por que.
  /// Aqui a variavel configurada e copiada para o nome que a politica conhece,
  /// quando esse ainda nao esta definido: a documentada passa a valer, e a que
  /// sempre valeu continua valendo.
  static Map<String, String> withIdentityFromConfig(
    Map<String, String> environment,
    DovetailConfig? config,
  ) {
    final String? named = config?.macos?.identityEnv;
    // Vazia e ausente: um runner de CI materializa um secret que nao existe
    // como string vazia, e e exatamente ai que a variavel documentada tem de
    // valer.
    final String? existing = environment['APPLE_SIGNING_IDENTITY'];
    if (named == null || (existing != null && existing.trim().isNotEmpty)) {
      return environment;
    }
    final String? value = environment[named];
    if (value == null || value.trim().isEmpty) {
      return environment;
    }
    return <String, String>{...environment, 'APPLE_SIGNING_IDENTITY': value};
  }

  /// O mesmo que [withIdentityFromConfig], para o Windows: `sign.windows`
  /// nomeia as variaveis do certificado e da senha, e traz a url do carimbo —
  /// e o signer so lia WINDOWS_CERTIFICATE_FILE, WINDOWS_CERTIFICATE_PASSWORD
  /// e WINDOWS_TIMESTAMP_URL. Tres chaves do yaml declaradas e ignoradas.
  static Map<String, String> withWindowsFromConfig(
    Map<String, String> environment,
    DovetailConfig? config,
  ) {
    final WindowsSigningConfig? windows = config?.windows;
    if (windows == null) {
      return environment;
    }
    bool isSet(String? value) => value != null && value.trim().isNotEmpty;
    final Map<String, String> out = <String, String>{...environment};
    if (!isSet(out['WINDOWS_CERTIFICATE_FILE']) &&
        isSet(environment[windows.certificateEnv])) {
      out['WINDOWS_CERTIFICATE_FILE'] = environment[windows.certificateEnv]!;
    }
    if (!isSet(out[OsslsigncodeCredentials.passwordVariable]) &&
        isSet(environment[windows.passwordEnv])) {
      out[OsslsigncodeCredentials.passwordVariable] =
          environment[windows.passwordEnv]!;
    }
    // A url do carimbo e configuracao publica, nao credencial — mas os dois
    // grupos de credenciais a contam como membro. Injeta-la SEMPRE fazia um
    // build local sem certificado virar "half configured", recusado depois
    // do build. So entra quando ha um certificado para carimbar.
    final bool hasCertificate =
        isSet(out['WINDOWS_CERTIFICATE_FILE']) ||
        isSet(out['WINDOWS_CERTIFICATE_THUMBPRINT']);
    if (hasCertificate &&
        !isSet(out['WINDOWS_TIMESTAMP_URL']) &&
        windows.timestampUrl != null) {
      out['WINDOWS_TIMESTAMP_URL'] = windows.timestampUrl!;
    }
    return out;
  }

  Future<int> _windows(
    ArgResults args,
    SigningPolicy policy,
    Map<String, String> processEnvironment,
  ) async {
    final Map<String, String> environment = withWindowsFromConfig(
      processEnvironment,
      projectContext(from: _root).config,
    );
    if (!Platform.isWindows ||
        args.option('certificate') != null ||
        environment.containsKey('WINDOWS_CERTIFICATE_FILE')) {
      return _windowsWithoutWindows(
        args,
        policy,
        _withOptions(args, environment),
      );
    }

    // Os arquivos existem? Antes da politica, para que um caminho errado seja
    // recusado mesmo quando nao ha credencial — senao a resposta a
    // `--file /nao/existe.exe` era "no credentials, so the artefact stays
    // unsigned", exit 0, sobre um artefato que nao existe.
    final List<String> files = _windowsFiles(args);

    final PolicyVerdict verdict = policy.decide(
      group: AuthenticodeCredentials.thumbprint,
      environment: environment,
    );
    stdout.writeln(verdict.note);
    if (!verdict.shouldSign) {
      return 0;
    }

    await const Authenticode(runner: SystemProcessRunner()).signAll(
      request: AuthenticodeRequest(
        thumbprint: environment['WINDOWS_CERTIFICATE_THUMBPRINT']!,
        timestampUrl: environment['WINDOWS_TIMESTAMP_URL']!,
      ),
      files: files,
    );
    stdout.writeln('signed ${files.length} file(s)');
    return 0;
  }

  /// Os arquivos que o Authenticode deve assinar, de `--file` e de
  /// `--directory` somados.
  ///
  /// Um instalador assinado cujos binarios internos nao foram assinados passa
  /// pelo SmartScreen e entao deposita executaveis sem assinatura no disco de
  /// quem instalou — que e o pior dos dois mundos, porque parece certo. Assinar
  /// o payload antes de empacotar e a unica ordem que funciona, e `--directory`
  /// existe para que essa ordem seja expressavel sem quem chama ter de listar
  /// cada DLL do Flutter e de cada plugin a mao.
  /// Existir vem antes de qualquer veredito sobre credenciais.
  ///
  /// A ordem importava e estava invertida: a politica decidia "sem credencial,
  /// fica sem assinar" e devolvia 0 antes de alguem olhar se o caminho
  /// existia. `sign --target macos --bundle /nao/existe.app` saia 0. A redacao
  /// segue a do Linux, que ja recusava certo.
  void _requireOnDisk(String path, {required String flag}) {
    if (!File(path).existsSync() && !Directory(path).existsSync()) {
      throw UsageException(
        'no artefact at $path.',
        'Nothing to sign there. $flag has to name a file or bundle that the '
            'build already produced — a signing step that reports success '
            'over a missing artefact is how an unsigned build reaches a '
            'customer.\n\n$usage',
      );
    }
  }

  List<String> _windowsFiles(ArgResults args) {
    final List<String> named = args.multiOption('file');
    final List<String> directories = args.multiOption('directory');
    for (final String each in named) {
      _requireOnDisk(each, flag: '--file');
    }
    final List<String> found = <String>[...named];

    for (final String each in directories) {
      final Directory directory = Directory(each);
      if (!directory.existsSync()) {
        throw UsageException('no directory at $each', usage);
      }
      final List<String> inside =
          directory
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .map((File file) => file.path)
              .where(
                (String path) =>
                    path.toLowerCase().endsWith('.exe') ||
                    path.toLowerCase().endsWith('.dll'),
              )
              .toList()
            ..sort();
      if (inside.isEmpty) {
        throw UsageException(
          'no .exe or .dll under $each.',
          'Signing nothing and reporting success is how an unsigned helper '
              'reaches a customer. Point --directory at the build output, '
              'which on Windows is build/windows/x64/runner/Release.\n\n$usage',
        );
      }
      found.addAll(inside);
    }

    if (found.isEmpty) {
      throw UsageException('windows needs --file or --directory', usage);
    }
    return found;
  }

  Map<String, String> _withOptions(
    ArgResults args,
    Map<String, String> environment,
  ) => <String, String>{
    ...environment,
    for (final MapEntry<String, String?> given in <String, String?>{
      'WINDOWS_CERTIFICATE_FILE': args.option('certificate'),
      OsslsigncodeCredentials.privateKeyVariable: args.option('private-key'),
      'WINDOWS_TIMESTAMP_URL': args.option('timestamp-url'),
    }.entries)
      if (given.value != null) given.key: given.value!,
  };

  Future<int> _windowsWithoutWindows(
    ArgResults args,
    SigningPolicy policy,
    Map<String, String> environment,
  ) async {
    // Existencia antes da politica, como no ramo nativo: um `--file` que nao
    // esta no disco tem de ser recusado mesmo sem credencial.
    final List<String> files = _windowsFiles(args);

    final PolicyVerdict verdict = policy.decide(
      group: OsslsigncodeCredentials.keyPair,
      environment: environment,
    );
    stdout.writeln(verdict.note);
    if (!verdict.shouldSign) {
      return 0;
    }

    final String? privateKey =
        environment[OsslsigncodeCredentials.privateKeyVariable];
    final Osslsigncode signer = Osslsigncode(
      runner: const SystemProcessRunner(),
      executable: args.option('osslsigncode')!,
    );
    final OsslsigncodeRequest request = OsslsigncodeRequest(
      certificatePath: environment['WINDOWS_CERTIFICATE_FILE']!,
      privateKeyPath: privateKey,
      password: privateKey != null
          ? null
          : policy.requirePassword(
              environment: environment,
              variable: OsslsigncodeCredentials.passwordVariable,
              label: OsslsigncodeCredentials.keyPair.label,
            ),
      timestampUrl: environment['WINDOWS_TIMESTAMP_URL']!,
      programName: args.option('program-name'),
    );

    for (final String file in files) {
      await signer.sign(request, file);
      stdout.writeln('signed $file');
    }
    return 0;
  }

  Future<int> _linux(ArgResults args) async {
    final String sums =
        await const ChecksumWriter(runner: SystemProcessRunner()).write(
          files: args.multiOption('file'),
          outputDirectory: args.option('out-dir')!,
        );
    stdout.writeln(sums);
    return 0;
  }

  /// The entitlements each nested binary is signed with, from the flags and
  /// from the project's own declaration.
  ///
  /// The declared half is the one that was missing. A product whose
  /// `service.macos` embeds a privileged component puts its binary inside the
  /// bundle, and `codesign` walking the bundle signs it with whatever the
  /// application got — including `app-sandbox`, which is the one thing that
  /// component must never inherit, because a sandboxed process reaches no
  /// socket and no disk outside its container. The key existed, was validated
  /// and was documented; nothing read it, so every daemon shipped so far was
  /// signed as if it were the app.
  ///
  /// Only the bundled route contributes. On the other one the component is
  /// installed from outside the `.app`, so there is no nested binary here to
  /// carry entitlements for.
  ///
  /// A flag for the same path wins over the declaration, and silently: the
  /// person typing the flag is looking at this signature now, and the yaml was
  /// written months ago.
  Map<String, String> _nestedEntitlements(
    ArgResults args, {
    required DovetailConfig? config,
    required String root,
  }) {
    final Map<String, String> byPath = <String, String>{};
    for (final String entry in args.multiOption('entitlements-for')) {
      final int divider = entry.indexOf('=');
      if (divider <= 0 || divider == entry.length - 1) {
        throw UsageException(
          'expected relative/path=entitlements.plist, got "$entry"',
          usage,
        );
      }
      final String relative = entry.substring(0, divider);
      final String plist = entry.substring(divider + 1);
      if (!File(plist).existsSync()) {
        throw UsageException('no entitlements file at $plist', usage);
      }
      if (byPath.containsKey(relative)) {
        throw UsageException(
          '"$relative" is given twice.',
          'A nested binary takes one entitlements file; the second would '
              'silently replace the first.\n\n$usage',
        );
      }
      byPath[relative] = plist;
    }

    final MacosServiceConfig? service = config?.service?.macos;
    if (service == null ||
        service.route != DarwinServiceRoute.bundled ||
        service.entitlements == null) {
      return byPath;
    }
    final String relative = DaemonEmbedder.programPathFor(service.program);
    if (byPath.containsKey(relative)) {
      return byPath;
    }
    final String plist = p.isAbsolute(service.entitlements!)
        ? service.entitlements!
        : p.join(root, service.entitlements!);
    if (!File(plist).existsSync()) {
      throw UsageException(
        'service.macos.entitlements points at $plist, and there is no file '
            'there.',
        'Signing would fall back to the application\'s own entitlements for '
            'the embedded component, which is the failure this key exists to '
            'prevent. Fix the path or drop the key.\n\n$usage',
      );
    }
    byPath[relative] = plist;
    stdout.writeln(
      'entitlements  $relative  '
      '(${p.relative(plist, from: root)}; service.macos.entitlements)',
    );
    return byPath;
  }

  /// `SMAppService` refuses a daemon whose Team ID differs from the
  /// application's — on the user's machine, at registration, with a message
  /// about which they can do nothing: an app cannot be re-signed from where
  /// the refusal shows up. [DarwinServiceRoute.bundled] writes the
  /// requirement down; this is what charges it, at the one moment somebody
  /// can still act on it — right after the signature that produced the
  /// mismatch. The app and the embedded binary are read with `codesign -dv`
  /// and compared; diverging is a refusal naming both values and where the
  /// daemon sits.
  ///
  /// Only the bundled route is charged: on the `system` route an installer
  /// running as root puts the binary in place from outside the `.app`, and
  /// there is nothing nested here whose Team ID has to match. A Team ID
  /// that cannot be read — an ad-hoc signature reports `not set` — is not a
  /// refusal either: nothing was compared, and the registration refusal the
  /// route already documents covers it. The skip path (no identity, no
  /// signature) never reaches this method, and has to keep ending in 0.
  Future<void> _requireSameTeamIdAsTheApp(
    String bundle,
    MacosServiceConfig? service,
  ) async {
    if (service == null || service.route != DarwinServiceRoute.bundled) {
      return;
    }
    final String daemon = p.join(
      bundle,
      DaemonEmbedder.programPathFor(service.program),
    );

    final ProcessOutcome appDisplay = await _signingRunner.run(
      'codesign',
      <String>['-dv', bundle],
    );
    if (!appDisplay.succeeded) {
      return;
    }
    final ProcessOutcome daemonDisplay = await _signingRunner.run(
      'codesign',
      <String>['-dv', daemon],
    );
    if (!daemonDisplay.succeeded) {
      throw SigningFailure(
        'the daemon the configuration embeds is not inside the bundle that '
        'was just signed.',
        remedy:
            '`codesign -dv` read nothing at $daemon, and a bundled daemon '
            'that signing never reached registers for nobody: SMAppService '
            'looks the property list up inside the app. Embed the binary '
            'before signing, which is what build does, or fix the '
            'service.macos.program name.',
      );
    }

    final String? appTeam = _teamIdOf(appDisplay);
    final String? daemonTeam = _teamIdOf(daemonDisplay);
    if (appTeam == null || daemonTeam == null || appTeam == daemonTeam) {
      return;
    }
    throw SigningFailure(
      'the embedded daemon and the application carry different Team IDs.',
      remedy:
          'the application signs with Team ID $appTeam, and the daemon at '
          '$daemon signs with $daemonTeam. SMAppService refuses the '
          'registration of a daemon whose Team ID differs from the app\'s, '
          'on the user\'s machine, with a message about which they can do '
          'nothing. Sign both with the same team.',
    );
  }

  /// The Team ID a `codesign -dv` display reports, or null when it reports
  /// none.
  ///
  /// The display is written on STDERR, not on stdout — and a runner is free
  /// to hand the two streams over merged, so the line is looked for in both
  /// places it can arrive. `TeamIdentifier=not set`, which is what an
  /// ad-hoc or missing signature reports, matches nothing: there is no
  /// value to compare, and nothing was compared.
  static String? _teamIdOf(ProcessOutcome outcome) => RegExp(
    r'TeamIdentifier=(\w{10})\b',
  ).firstMatch('${outcome.stdout}\n${outcome.stderr}')?.group(1);
}
