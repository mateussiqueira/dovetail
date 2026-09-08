import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_cli/src/config/config_locator.dart';
import 'package:dovetail_cli/src/config/config_template.dart';
import 'package:dovetail_cli/src/config/dovetail_config.dart';
import 'package:dovetail_cli/src/config/project_probe.dart';
import 'package:dovetail_cli/src/config/pubspec_version.dart';
import 'package:dovetail_cli/src/sdk/sdk_locator.dart';
import 'package:dovetail_cli/src/sdk/sdk_overrides.dart';
import 'package:path/path.dart' as p;

final class InitCommand extends Command<int> {
  InitCommand({this._sdkLocator}) {
    argParser
      ..addOption('root', help: 'the project directory; defaults to the cwd')
      ..addOption('identifier', help: 'reverse-dns id, if none can be detected')
      ..addFlag(
        'force',
        negatable: false,
        help: 'overwrite an existing dovetail.yaml',
      )
      ..addFlag(
        'sdk',
        negatable: false,
        help:
            'resolve the runtime from the installed SDK via '
            'pubspec_overrides.yaml, instead of the pubspec',
      );
  }

  final SdkLocator? _sdkLocator;

  @override
  String get name => 'init';

  @override
  String get description =>
      'Reads the project and writes the dovetail.yaml the other commands use.';

  @override
  Future<int> run() async {
    final String root = argResults?.option('root') ?? Directory.current.path;
    final File target = File(p.join(root, ConfigLocator.fileName));

    if (target.existsSync() && !(argResults?.flag('force') ?? false)) {
      throw UsageException(
        'there is already a ${ConfigLocator.fileName} at ${target.path}.',
        'Pass --force to overwrite it. Overwriting discards whatever was '
            'configured by hand, which is why it is not the default.\n\n$usage',
      );
    }

    final ProjectProbe probe = ProjectProbe(root);
    if (!File(p.join(root, PubspecVersion.fileName)).existsSync()) {
      throw UsageException(
        'no ${PubspecVersion.fileName} in $root.',
        'dovetail init reads the project rather than asking, so it has to be '
            'run from the project root, or pointed at it with --root.\n\n$usage',
      );
    }

    if (probe.targets.isEmpty) {
      throw UsageException(
        'this project has no macos, windows or linux directory.',
        'dovetail configures a desktop build, and there is none here to '
            'configure. Add the platforms first:\n'
            '  flutter create --platforms=macos,windows,linux .\n\n$usage',
      );
    }

    // O SDK é localizado antes de qualquer arquivo ser escrito: um --sdk sem
    // SDK instalado sai sem deixar a config pela metade nem o override de fora.
    final SdkInstall? sdk = (argResults?.flag('sdk') ?? false)
        ? _requireSdk()
        : null;

    final String rendered = ConfigTemplate.render(
      probe,
      identifier: argResults?.option('identifier'),
    );

    DovetailConfig.parse(rendered, origin: target.path);

    target.writeAsStringSync(rendered);

    stdout
      ..writeln('wrote ${target.path}')
      ..writeln();
    _report(probe, root);
    if (sdk != null) {
      _writeSdkOverrides(root, sdk);
    }
    return 0;
  }

  SdkInstall _requireSdk() {
    final SdkLocator locator = _sdkLocator ?? SdkLocator();
    return SdkOverrides.requireSdk(locator, usage);
  }

  void _writeSdkOverrides(String root, SdkInstall sdk) {
    final File target = File(p.join(root, SdkOverrides.fileName));
    target.writeAsStringSync(SdkOverrides.render(sdk));

    stdout
      ..writeln('wrote ${target.path}')
      ..writeln('  the runtime resolves from the SDK at ${sdk.packagesDir}')
      ..writeln(
        '  (${sdk.packages().length} packages, version ${sdk.version})',
      );
  }

  void _report(ProjectProbe probe, String root) {
    final List<String> targets = probe.targets;
    stdout.writeln(
      targets.isEmpty
          ? 'targets    none detected — no macos/, windows/ or linux/ here'
          : 'targets    ${targets.join(', ')}',
    );

    final Map<String, String> declared = probe.declaredIdentifiers;
    final String? identifier =
        argResults?.option('identifier') ?? probe.declaredIdentifier;
    stdout.writeln(
      identifier == null
          ? 'identifier not detected — a placeholder was written, change it'
          : 'identifier $identifier',
    );

    final Set<String> distinct = declared.values.toSet();
    if (argResults?.option('identifier') == null && distinct.length > 1) {
      stdout.writeln();
      stdout.writeln(
        'this project declares more than one identifier, and the guard that '
        'keeps a second instance from opening keys off it:',
      );
      for (final MapEntry<String, String> entry in declared.entries) {
        stdout.writeln('  ${entry.value}  ${entry.key}');
      }
      stdout.writeln(
        'the first was written; make the platforms agree, or pass '
        '--identifier.',
      );
    }

    stdout.writeln('version    ${PubspecVersion.read(root)}  (from pubspec)');

    final String? icon = probe.iconPath;
    if (icon != null) {
      stdout.writeln('icon       $icon');
    }

    stdout
      ..writeln()
      ..writeln('next: dovetail doctor');
  }
}
