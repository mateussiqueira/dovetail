import 'dart:io';
import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:dovetail_cli/src/config/config_failure.dart';
import 'package:dovetail_cli/src/config/config_locator.dart';
import 'package:dovetail_cli/src/probe/manifest_probe.dart';
import 'package:dovetail_cli/src/command/required_option.dart';

/// The three the product ships to. A manifest that serves one of them and
/// five hundreds the other two is the shape production is in today, and the
/// default is what makes the probe say so without being asked.
const List<String> _defaultTargets = <String>[
  'darwin-universal',
  'windows-x86_64',
  'linux-x86_64',
];

final class ProbeCommand extends Command<int> {
  ProbeCommand({this._fetcher}) {
    argParser
      ..addOption(
        'url',
        help: 'https url of the manifest the installed clients read',
      )
      ..addOption(
        'timeout',
        defaultsTo: '15',
        help:
            'seconds to wait for the endpoint to connect, answer, or send the '
            'next chunk; 0 waits as long as the OS does',
      )
      ..addMultiOption(
        'target',
        help:
            'platform key; repeatable. Defaults to the three the product '
            'ships to.',
      )
      ..addOption(
        'public-key',
        help: 'path to the minisign public key the shipped client trusts',
      )
      ..addOption(
        'ca',
        help:
            'PEM of an extra root CA to trust for this run only; the system '
            'roots stay, and so do the chain and hostname checks. For a '
            'staging host with a private CA — never a way to skip TLS.',
      )
      ..addOption(
        'installed',
        help: 'the version a client would be running, to exercise the policy',
      )
      ..addFlag(
        'download',
        negatable: false,
        help: 'also fetch each artefact and verify the signature over it',
      );
  }

  /// Injetado nos testes; em producao nasce em `run()`, porque o limite de
  /// tempo vem da flag e a flag so existe depois do parse.
  final ArtifactFetcher? _fetcher;

  /// Um HttpClient que confia nas raizes do sistema E na CA em [caPath].
  /// Nenhum badCertificateCallback: cadeia e hostname continuam verificados.
  static HttpClient clientTrusting(String caPath) => HttpClient(
    context: SecurityContext(withTrustedRoots: true)
      ..setTrustedCertificates(caPath),
  );

  @override
  String get name => 'probe';

  @override
  String get description =>
      'Asks an update endpoint whether it serves something this client can '
      'use, from outside, over the wire.';

  @override
  Future<int> run() async {
    final ArgResults args = argResults!;

    final Uri url;
    try {
      url = Uri.parse(requiredOption(args, 'url', usage));
    } on FormatException catch (error) {
      throw UsageException('--url is not a url: ${error.message}', usage);
    }

    // Sem limite, um endpoint morto deixava o probe mudo por minutos — sem
    // dizer se estava pensando ou travado. Quinze segundos e o padrao; zero
    // devolve a espera do SO para quem quer exatamente isso.
    final String timeoutGiven = args.option('timeout')!;
    final int? timeoutSeconds = int.tryParse(timeoutGiven);
    if (timeoutSeconds == null || timeoutSeconds < 0) {
      throw UsageException(
        '--timeout "$timeoutGiven" is not a number of seconds.',
        usage,
      );
    }

    final List<String> targets = args.multiOption('target').isEmpty
        ? _defaultTargets
        : args.multiOption('target');
    for (final String target in targets) {
      // Fail on the vocabulary before the network: a typo in a platform key
      // otherwise comes back as "the manifest does not offer this", which
      // blames the server for a mistake made here.
      try {
        PlatformKey.validate(target);
      } on UpdateFailure catch (failure) {
        throw UsageException('--target $target: ${failure.message}', usage);
      }
    }

    final String? caPath = args.option('ca');
    if (caPath != null && !File(caPath).existsSync()) {
      throw UsageException('no CA at $caPath', usage);
    }

    final String? keyPath = args.option('public-key');
    String? publicKey;
    if (keyPath != null) {
      final File file = File(keyPath);
      if (!file.existsSync()) {
        throw UsageException('no public key at $keyPath', usage);
      }
      publicKey = file.readAsStringSync();
    } else {
      // Sem a flag, a chave e a do dovetail.yaml ao lado: o mesmo arquivo com
      // que o release assina e que o build embute no app. Um yaml que nao
      // parseia nao derruba uma sonda que nunca precisou dele — vira nota.
      try {
        publicKey = ConfigLocator.load()?.update?.publicKey;
      } on ConfigFailure catch (failure) {
        stdout.writeln(
          '  note   dovetail.yaml could not be read (${failure.message}); '
          'pass --public-key to verify signatures',
        );
      }
      if (publicKey != null) {
        stdout.writeln(
          '  note   public key from dovetail.yaml (update.public-key)',
        );
      }
    }

    Version? installed;
    final String? given = args.option('installed');
    if (given != null) {
      try {
        installed = Version.parse(given);
      } on FormatException {
        throw UsageException('--installed "$given" is not a version', usage);
      }
    }

    if (args.flag('download') && publicKey == null) {
      throw UsageException(
        '--download without --public-key proves nothing.',
        'Verifying an artefact against the key that signed it only says the '
            'two came from the same place. Pass the key the shipped client '
            'trusts.\n\n$usage',
      );
    }

    // Uma raiz A MAIS, nunca um badCertificateCallback: a cadeia e o hostname
    // continuam sendo verificados, so que contra uma CA que o SO nao conhece.
    // E o que permite provar transporte e assinatura contra um host local sem
    // ensinar o cliente a aceitar qualquer coisa.
    HttpClient? trusting;
    if (caPath != null) {
      try {
        trusting = clientTrusting(caPath);
      } on TlsException catch (error) {
        throw UsageException(
          '--ca $caPath is not a PEM certificate: ${error.message}',
          usage,
        );
      }
    }
    final ArtifactFetcher fetcher =
        _fetcher ??
        HttpArtifactFetcher(
          client: trusting,
          timeout: timeoutSeconds == 0
              ? null
              : Duration(seconds: timeoutSeconds),
        );
    if (caPath != null) {
      stdout.writeln('  note   transport trusts an extra CA: $caPath');
    }
    final ProbeReport report = await ManifestProbe(fetcher: fetcher).run(
      url: url,
      targets: targets,
      publicKey: publicKey,
      installed: installed,
      download: args.flag('download'),
    );

    for (final ProbeFinding finding in report.findings) {
      stdout.writeln('  $finding');
    }
    stdout.writeln();
    stdout.writeln(
      report.passed
          ? 'probe: ok — this endpoint serves what the client reads'
          : 'probe: FAILED — ${report.failures} check(s)',
    );
    return report.passed ? 0 : 1;
  }
}
