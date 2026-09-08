import 'dart:io';

import 'package:args/args.dart';
import 'package:dovetail_signer/dovetail_signer.dart';

Future<void> main(List<String> arguments) async {
  final ArgParser parser = ArgParser()
    ..addOption(
      'target',
      allowed: <String>['macos', 'windows', 'linux'],
      mandatory: true,
    )
    ..addMultiOption('file', help: 'artefact to sign; repeatable')
    ..addOption(
      'bundle',
      help:
          'the .app to sign and notarise on macOS; --file there is the .dmg, '
          'signed as a flat file and notarised itself',
    )
    ..addOption('entitlements')
    ..addOption('out-dir', defaultsTo: '.')
    ..addFlag('require-signature', negatable: false)
    ..addFlag('notarize', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exit(64);
  }

  if (args.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }

  final Map<String, String> environment = Platform.environment;
  final SigningPolicy policy = SigningPolicy(
    requireSignature: args.flag('require-signature'),
  );

  try {
    switch (args.option('target')) {
      case 'macos':
        await _signMacos(args, policy, environment);
      case 'windows':
        await _signWindows(args, policy, environment);
      case 'linux':
        await _writeChecksums(args);
    }
  } on SigningFailure catch (failure) {
    stderr.writeln(failure.toString());
    exit(1);
  }
}

Future<void> _signMacos(
  ArgResults args,
  SigningPolicy policy,
  Map<String, String> environment,
) async {
  final String? bundle = args.option('bundle');
  final List<String> files = args.multiOption('file');
  if (bundle == null && files.isEmpty) {
    throw const SigningFailure(
      'macos needs --bundle (the .app) or --file (the .dmg).',
    );
  }
  if (bundle != null && files.isNotEmpty) {
    throw const SigningFailure(
      'macos signs --bundle or --file in one call, not both.',
      remedy:
          'The .app is signed inside out with its entitlements; the .dmg is '
          'a flat file signed after it is built. Two calls, in that order.',
    );
  }

  final PolicyVerdict verdict = policy.decide(
    group: NotarizationCredentials.identity,
    environment: environment,
  );
  stdout.writeln(verdict.note);
  if (!verdict.shouldSign) {
    return;
  }

  const MacosSigner signer = MacosSigner(runner: SystemProcessRunner());
  final String identity =
      environment[NotarizationCredentials.identity.members.single.name]!;

  if (bundle == null) {
    // O contentor: arquivo plano, sem hardened runtime nem entitlements, e
    // notarizado ele mesmo — e o que se baixa e o que o Gatekeeper avalia.
    for (final String file in files) {
      await signer.signFile(path: file, identity: identity);
      stdout.writeln('signed $file');
    }
    if (!args.flag('notarize')) {
      return;
    }
    for (final String file in files) {
      final NotarizationOutcome outcome = await const NotarizationStep(
        runner: SystemProcessRunner(),
      ).runOnFile(path: file, environment: environment);
      stdout.writeln(
        outcome == NotarizationOutcome.notarised
            ? 'notarised and stapled $file'
            : 'no notarisation credentials are set; nothing was submitted',
      );
    }
    return;
  }

  final List<String> contents = Directory(bundle)
      .listSync(recursive: true, followLinks: false)
      .map((FileSystemEntity entity) => entity.path)
      .toList();

  await signer.sign(
    request: MacosSigningRequest(
      bundlePath: bundle,
      identity: identity,
      appEntitlements: args.option('entitlements'),
    ),
    contents: contents,
  );
  stdout.writeln('signed $bundle');

  if (!args.flag('notarize')) {
    return;
  }

  final NotarizationOutcome outcome = await const NotarizationStep(
    runner: SystemProcessRunner(),
  ).run(bundlePath: bundle, environment: environment);

  stdout.writeln(
    outcome == NotarizationOutcome.notarised
        ? 'notarised and stapled $bundle'
        : 'no notarisation credentials are set; nothing was submitted',
  );
}

Future<void> _signWindows(
  ArgResults args,
  SigningPolicy policy,
  Map<String, String> environment,
) async {
  final PolicyVerdict verdict = policy.decide(
    group: AuthenticodeCredentials.thumbprint,
    environment: environment,
  );
  stdout.writeln(verdict.note);
  if (!verdict.shouldSign) {
    return;
  }

  await const Authenticode(runner: SystemProcessRunner()).signAll(
    request: AuthenticodeRequest(
      thumbprint: environment['WINDOWS_CERTIFICATE_THUMBPRINT']!,
      timestampUrl: environment['WINDOWS_TIMESTAMP_URL']!,
    ),
    files: args.multiOption('file'),
  );
  stdout.writeln('signed ${args.multiOption('file').length} file(s)');
}

Future<void> _writeChecksums(ArgResults args) async {
  final String sums = await const ChecksumWriter(runner: SystemProcessRunner())
      .write(
        files: args.multiOption('file'),
        outputDirectory: args.option('out-dir')!,
      );
  stdout.writeln(sums);
}
