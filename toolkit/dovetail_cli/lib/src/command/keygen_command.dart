import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:dovetail_signer/dovetail_signer.dart';
import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:dovetail_cli/src/config/config_failure.dart';
import 'package:dovetail_cli/src/config/config_locator.dart';
import 'package:dovetail_cli/src/config/dovetail_config.dart';
import 'package:dovetail_cli/src/config/update_config.dart';
import 'package:path/path.dart' as p;

/// The pair every installed client is measured against.
///
/// `dovetail init` writes `update.key: keys/update.key` and there was nothing
/// that made the file, so the one thing the whole project exists for — a
/// release the installed park accepts — had no first step. This is that step,
/// and it is deliberately the only command that can refuse to run twice.
final class KeygenCommand extends Command<int> {
  KeygenCommand() {
    argParser
      ..addOption('root', help: 'the project directory; defaults to the cwd')
      ..addOption('out', help: 'defaults to update.key in dovetail.yaml')
      ..addOption(
        'password-env',
        help: 'name of the variable holding the password for the new key',
      )
      ..addFlag(
        'unencrypted',
        negatable: false,
        help: 'the key will have no password, and you are saying so on purpose',
      )
      ..addOption('minisign', defaultsTo: 'minisign');
  }

  @override
  String get name => 'keygen';

  @override
  String get description =>
      'Creates the minisign pair a release is signed with, once.';

  @override
  Future<int> run() async {
    final ArgResults args = argResults!;

    final String? from = args.option('root');
    final File? configFile = ConfigLocator.findFile(from: from);
    final String root = configFile == null
        ? (from ?? Directory.current.path)
        : ConfigLocator.rootFor(configFile);
    final UpdateConfig? update = configFile == null
        ? null
        : DovetailConfig.parse(
            configFile.readAsStringSync(),
            origin: configFile.path,
          ).update;

    final String? declared = args.option('out') ?? update?.keyPath;
    if (declared == null) {
      throw UsageException(
        'no key path: there is no dovetail.yaml here and no --out.',
        'Run dovetail init first, or say where the key goes:\n'
            '  dovetail keygen --out keys/update.key\n\n$usage',
      );
    }

    final String secretPath = p.isAbsolute(declared)
        ? declared
        : p.join(root, declared);
    final String publicPath = _publicFor(secretPath);

    // Overwriting is how a park is orphaned: every client keeps trusting the
    // old public half, and nothing signed by the new key is ever installed
    // again. There is no --force, because the recovery is to ship a new
    // installer to every machine, and that is not a flag.
    for (final String path in <String>[secretPath, publicPath]) {
      if (File(path).existsSync()) {
        throw ConfigFailure(
          'there is already a key at $path.',
          remedy:
              'Replacing it strands every client that trusts the current one: '
              'they cannot learn a new public key from a manifest, only from '
              'an installer. Move the old pair aside by hand if you really '
              'mean to rotate.',
        );
      }
    }

    final SecretKeyAccess access = _accessFrom(args, update);
    Directory(p.dirname(secretPath)).createSync(recursive: true);

    final ProcessOutcome made = await const SystemProcessRunner().run(
      args.option('minisign')!,
      <String>[
        '-G',
        '-f',
        if (access is UnencryptedKey) '-W',
        '-p',
        publicPath,
        '-s',
        secretPath,
      ],
      stdin: access is PasswordProtectedKey
          ? '${access.password}\n${access.password}\n'
          : null,
    );
    if (!made.succeeded) {
      throw ConfigFailure(
        'minisign could not generate the pair: ${made.stderr.trim()}',
        remedy:
            'dovetail drives minisign rather than reimplementing it, so the '
            'key it makes is the key the reference tool verifies.',
      );
    }

    final String publicText = File(publicPath).readAsStringSync();
    final String wrapped = base64.encode(utf8.encode(publicText));
    final String keyId = MinisignPublicKey.parse(publicText).keyIdHex;

    stdout
      ..writeln('secret  ${p.relative(secretPath, from: root)}  (key $keyId)')
      ..writeln('public  ${p.relative(publicPath, from: root)}')
      ..writeln()
      ..writeln('Put this in dovetail.yaml, so a release signed by any other')
      ..writeln('key is refused before it reaches a machine you cannot see:')
      ..writeln()
      ..writeln('update:')
      ..writeln('  public-key: $wrapped')
      ..writeln()
      ..writeln('And this is what the app passes to the updater:')
      ..writeln()
      ..writeln("  UpdateFlow(publicKey: '$wrapped')")
      ..writeln();

    _warnIfTracked(root: root, secretPath: secretPath);
    return 0;
  }

  static String _publicFor(String secretPath) {
    final String extension = p.extension(secretPath);
    final String withoutExtension = extension.isEmpty
        ? secretPath
        : secretPath.substring(0, secretPath.length - extension.length);
    return '$withoutExtension.pub';
  }

  static SecretKeyAccess _accessFrom(ArgResults args, UpdateConfig? update) {
    if (args.flag('unencrypted')) {
      return const UnencryptedKey();
    }
    if (update != null &&
        update.unencrypted &&
        args.option('password-env') == null) {
      return const UnencryptedKey();
    }

    final String variable =
        args.option('password-env') ??
        update?.passwordEnv ??
        'DOVETAIL_UPDATE_KEY_PASSWORD';
    final String? password = Platform.environment[variable];
    if (password == null || password.isEmpty) {
      throw ConfigFailure(
        '$variable is not set, so there is no password for the new key.',
        remedy:
            'An empty password is never assumed — that is the Tauri behaviour '
            'this refuses to copy. Export it, or pass --unencrypted to say on '
            'purpose that this key carries none.',
      );
    }
    return PasswordProtectedKey(password);
  }

  static void _warnIfTracked({
    required String root,
    required String secretPath,
  }) {
    final ProcessResult ignored = Process.runSync('git', <String>[
      'check-ignore',
      '-q',
      secretPath,
    ], workingDirectory: root);
    if (ignored.exitCode == 0) {
      return;
    }
    stderr
      ..writeln('warning: ${p.relative(secretPath, from: root)} is not ignored')
      ..writeln(
        '  A committed secret key is a key the whole park has to be moved off '
        'of. Add it to .gitignore before the next commit.',
      );
  }
}
