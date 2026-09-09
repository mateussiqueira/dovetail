import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:dovetail_signer/dovetail_signer.dart';
import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:dovetail_cli/src/config/config_failure.dart';
import 'package:dovetail_cli/src/config/config_locator.dart';
import 'package:dovetail_cli/src/config/dovetail_config.dart';
import 'package:dovetail_cli/src/config/pubspec_version.dart';
import 'package:dovetail_cli/src/config/update_config.dart';
import 'package:path/path.dart' as p;

final class _Artifact {
  const _Artifact({
    required this.platformKey,
    required this.url,
    required this.path,
  });

  final String platformKey;
  final String url;
  final String path;
}

final class ReleaseCommand extends Command<int> {
  ReleaseCommand() {
    argParser
      ..addOption('root', help: 'the project directory; defaults to the cwd')
      ..addOption('version', help: 'defaults to the version in pubspec.yaml')
      ..addOption('notes')
      ..addOption('out', help: 'defaults to update.manifest in dovetail.yaml')
      ..addOption(
        'key',
        help: 'the minisign secret key every installed client already trusts',
      )
      ..addOption(
        'password-env',
        help: 'name of the variable holding the key password',
      )
      ..addFlag(
        'unencrypted-key',
        negatable: false,
        help: 'the key has no password, and you are saying so on purpose',
      )
      ..addOption(
        'public-key',
        help:
            'the public key the shipped app trusts — a file or the key '
            'itself. Required unless dovetail.yaml declares '
            'update.public-key; without one, nothing can check that this '
            'release is signed by a key any client accepts',
      )
      ..addOption('minisign', defaultsTo: 'minisign')
      ..addMultiOption(
        'artifact',
        help:
            'platformKey=url=path ; repeatable. With update.base-url set in '
            'dovetail.yaml, platformKey=path is enough',
      );
  }

  @override
  String get name => 'release';

  @override
  String get description =>
      'Signs each built artefact and writes the manifest that points at them.';

  /// Tauri compares the two key ids, warns, and finishes the build. The
  /// result is a release that verifies against nothing in the field, and the
  /// discovery happens on a stranger's machine. Here it is fatal, because a
  /// release nobody can install is not a release.
  static void _refuseAForeignKey({
    required String signed,
    required String? declared,
  }) {
    // Declarar a chave e OBRIGATORIO, e nao um detalhe opcional que quem
    // quiser preenche.
    //
    // Esta guarda existia e nunca disparou, porque saia aqui quando o yaml
    // omitia `public-key` — e o yaml do produto omitia. O resultado foi um
    // release assinado com a chave de dev (D18395BE8A6B994E) que o app,
    // compilado para confiar noutra, recusa. A checagem
    // mais importante do comando era a mais facil de desligar: bastava nao
    // escrever a linha.
    //
    // Uma release sem par declarado nao e verificavel por definicao, entao
    // recusar aqui nao tira nada de ninguem: tira a ilusao de ter passado.
    if (declared == null) {
      throw _noDeclaredKey;
    }
    final String trusted = MinisignPublicKey.parse(declared).keyIdHex;
    if (trusted == signed) {
      return;
    }
    throw ConfigFailure(
      'the secret key signs as $signed, and update.public-key is $trusted.',
      remedy:
          'Every client in the field carries $trusted, so it refuses anything '
          'signed by $signed. Either point update.key at the key that pairs '
          'with the declared public one, or — if the park really is being '
          'moved to a new key — ship the new public key in an installer '
          'first, because the running clients cannot learn it from a '
          'manifest.',
    );
  }

  static const ConfigFailure _noDeclaredKey = ConfigFailure(
    'no public key is declared, so nothing can check that this release is '
    'signed with the key the installed clients trust.',
    remedy:
        'Declare the public key the shipped app carries — update.public-key '
        'in dovetail.yaml, or --public-key <file or key>. It is public by '
        'definition; the secret one stays out of the repository. Without it a '
        'release can be signed by any key and still look fine here, which is '
        'exactly how a release went out signed by a key no client in the '
        'field accepts.',
  );

  /// `--public-key` como caminho OU como a chave em si.
  ///
  /// As duas formas porque as duas aparecem: numa maquina de release a chave
  /// publica e um arquivo ao lado da secreta, e num runner ela chega por
  /// secret, como texto. Um caminho relativo resolve contra a RAIZ do projeto
  /// primeiro, como `--artifact`, `update.key` e `update.manifest` ja fazem —
  /// `release --root product/x --public-key keys/update.pub` da raiz do repo
  /// lia "keys/update.pub" contra o cwd, nao achava, e tratava o TEXTO do
  /// caminho como a chave.
  static String? _publicKeyOption(ArgResults args, String? root) {
    final String? given = args.option('public-key')?.trim();
    if (given == null || given.isEmpty) {
      return null;
    }
    if (root != null && !p.isAbsolute(given)) {
      final File beside = File(p.join(root, given));
      if (beside.existsSync()) {
        return beside.readAsStringSync();
      }
    }
    final File file = File(given);
    return file.existsSync() ? file.readAsStringSync() : given;
  }

  @override
  Future<int> run() async {
    final ArgResults args = argResults!;

    final File? configFile = ConfigLocator.findFile(from: args.option('root'));
    final DovetailConfig? config = configFile == null
        ? null
        : DovetailConfig.parse(
            configFile.readAsStringSync(),
            origin: configFile.path,
          );
    final String? root = configFile == null
        ? args.option('root')
        : ConfigLocator.rootFor(configFile);
    final UpdateConfig? update = config?.update;

    final String version = _versionFrom(args, root);
    final List<_Artifact> artifacts = _artifactsFrom(
      args.multiOption('artifact'),
      update: update,
      version: version,
      declaredTargets: config?.targets,
      root: root,
    );
    final String keyPath = _keyFrom(args, update, root);
    final SecretKeyAccess access = _accessFrom(args, update);

    // Antes de assinar, e nao no meio do laco: assinar tres artefatos para
    // entao recusar gasta trabalho e deixa `.minisig` orfaos no disco.
    //
    // A flag vence o yaml, como `--version`, `--key` e `--out` ja venciam.
    // Era o contrario, e a consequencia aparecia no dia em que o yaml de
    // producao declara a chave do parque: nenhum release de staging com um par
    // descartavel era possivel sem editar o yaml de producao, porque a chave
    // declarada la recusava a que assinou. Quando vence, diz.
    final String? flagKey = _publicKeyOption(args, root);
    final String? declaredKey = flagKey ?? update?.publicKey;
    if (declaredKey == null) {
      throw _noDeclaredKey;
    }
    if (flagKey != null && update?.publicKey != null) {
      _sayWhichKeyWon(flag: flagKey, yaml: update!.publicKey!);
    }

    final UpdateSigner signer = UpdateSigner(
      runner: const SystemProcessRunner(),
      minisign: args.option('minisign')!,
    );

    final List<ManifestEntry> entries = <ManifestEntry>[];
    String keyId = '';

    for (final _Artifact artifact in artifacts) {
      final UpdateSignature signature = await signer.sign(
        artifactPath: artifact.path,
        secretKeyPath: keyPath,
        access: access,
        trustedComment:
            'version:$version\t'
            'file:${p.basename(artifact.path)}',
      );

      keyId = signature.keyIdHex;
      _refuseAForeignKey(signed: signature.keyIdHex, declared: declaredKey);
      entries.add(
        ManifestEntry(
          platformKey: artifact.platformKey,
          url: artifact.url,
          signature: signature.content,
        ),
      );
      stdout.writeln(
        'signed  ${artifact.platformKey}  ${p.basename(signature.signaturePath)}',
      );
    }

    final String out = _outFrom(args, update, root);
    File(out)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        ManifestWriter.render(
          version: version,
          notes: args.option('notes'),
          entries: entries,
        ),
      );

    stdout.writeln('manifest  $out  (key $keyId)');
    return 0;
  }

  static void _sayWhichKeyWon({required String flag, required String yaml}) {
    String idOf(String key) {
      try {
        return MinisignPublicKey.parse(key).keyIdHex;
      } on UpdateFailure {
        return 'unparseable';
      }
    }

    final String flagId = idOf(flag);
    final String yamlId = idOf(yaml);
    if (flagId != yamlId) {
      stdout.writeln(
        'public key  --public-key overrides update.public-key: $flagId '
        'instead of $yamlId',
      );
    }
  }

  String _versionFrom(ArgResults args, String? root) {
    final String? given = args.option('version');
    if (given != null && given.isNotEmpty) {
      return given;
    }
    if (root == null) {
      throw UsageException(
        'no --version, and no dovetail.yaml to read one beside.',
        'Run dovetail init, or pass --version.\n\n$usage',
      );
    }
    return PubspecVersion.read(root);
  }

  String _keyFrom(ArgResults args, UpdateConfig? update, String? root) {
    final String? given = args.option('key');
    if (given != null && given.isNotEmpty) {
      return given;
    }
    if (update == null || root == null) {
      throw UsageException(
        'no --key, and no update.key in dovetail.yaml.',
        'An unsigned release is one no installed client will accept, so this '
            'refuses rather than writing a manifest without '
            'signatures.\n\n$usage',
      );
    }
    return p.isAbsolute(update.keyPath)
        ? update.keyPath
        : p.join(root, update.keyPath);
  }

  String _outFrom(ArgResults args, UpdateConfig? update, String? root) {
    final String? given = args.option('out');
    if (given != null && given.isNotEmpty) {
      // Relativo resolve contra a raiz, como `--artifact` e `update.manifest`;
      // `--root` diz onde o projeto esta, e metade dos caminhos ignorava isso.
      return root == null || p.isAbsolute(given) ? given : p.join(root, given);
    }
    if (update == null || root == null) {
      return 'latest.json';
    }
    return p.isAbsolute(update.manifestPath)
        ? update.manifestPath
        : p.join(root, update.manifestPath);
  }

  List<_Artifact> _artifactsFrom(
    List<String> raw, {
    required UpdateConfig? update,
    required String version,
    required List<String>? declaredTargets,
    required String? root,
  }) {
    if (raw.isEmpty) {
      throw UsageException('at least one --artifact is needed.', usage);
    }

    final List<_Artifact> artifacts = <_Artifact>[];
    final Set<String> platformKeys = <String>{};

    for (final String entry in raw) {
      final int afterKey = entry.indexOf('=');
      if (afterKey <= 0 || afterKey == entry.length - 1) {
        throw UsageException(
          'expected platformKey=url=artifactPath, got "$entry"',
          usage,
        );
      }

      final String platformKey = entry.substring(0, afterKey);
      final int beforePath = entry.lastIndexOf('=');

      final String path;
      final String url;
      if (beforePath == afterKey) {
        path = entry.substring(afterKey + 1);
        if (update?.baseUrl == null) {
          throw UsageException(
            'no url in "$entry", and no update.base-url is configured.',
            'Either write platformKey=url=path, or set update.base-url in '
                'dovetail.yaml and let it build '
                '<base-url>/<version>/<file>.\n\n$usage',
          );
        }
        url = update!.urlFor(version: version, fileName: p.basename(path));
      } else {
        url = entry.substring(afterKey + 1, beforePath);
        path = entry.substring(beforePath + 1);
      }

      try {
        PlatformKey.validate(platformKey);
      } on UpdateFailure catch (failure) {
        throw UsageException(failure.message, '${failure.remedy}\n\n$usage');
      }

      if (!platformKeys.add(platformKey)) {
        throw UsageException(
          'the platform "$platformKey" is given twice.',
          'A manifest holds one artefact per platform; the second would '
              'silently replace the first.\n\n$usage',
        );
      }
      if (url.isEmpty) {
        throw UsageException('the url for $platformKey is empty.', usage);
      }
      if (!_declares(declaredTargets, platformKey)) {
        throw UsageException(
          '"$platformKey" is not one of the targets this product declares.',
          'dovetail.yaml lists ${declaredTargets!.join(', ')}. Publishing a '
              'key outside that list ships an artefact no client asks for; '
              'add it to targets if it is meant to exist.\n\n$usage',
        );
      }
      // Relative artefact paths resolve against the project, the same way
      // update.key and update.manifest already do. Without this, --root says
      // where the project is and then half the paths ignore it.
      final String resolved = root == null || p.isAbsolute(path)
          ? path
          : p.join(root, path);
      if (!File(resolved).existsSync()) {
        throw UsageException('no artefact at $resolved', usage);
      }
      artifacts.add(
        _Artifact(platformKey: platformKey, url: url, path: resolved),
      );
    }
    return artifacts;
  }

  bool _declares(List<String>? declaredTargets, String platformKey) {
    if (declaredTargets == null || declaredTargets.isEmpty) {
      return true;
    }
    if (declaredTargets.contains(platformKey)) {
      return true;
    }

    final int divider = platformKey.indexOf('-');
    if (divider <= 0 ||
        platformKey.substring(divider + 1) != PlatformKey.universalArch) {
      return false;
    }
    final String os = platformKey.substring(0, divider);
    return declaredTargets.any((String key) => key.startsWith('$os-'));
  }

  SecretKeyAccess _accessFrom(ArgResults args, UpdateConfig? update) {
    if (args.flag('unencrypted-key')) {
      return const UnencryptedKey();
    }

    final String variable =
        args.option('password-env') ??
        update?.passwordEnv ??
        'DOVETAIL_UPDATE_KEY_PASSWORD';
    final String? password = Platform.environment[variable];
    if (password == null || password.isEmpty) {
      throw UsageException(
        '$variable is not set.',
        'An empty password is never assumed. Export the variable, or pass '
            '--unencrypted-key if the key genuinely has none.\n\n$usage',
      );
    }
    return PasswordProtectedKey(password);
  }
}
