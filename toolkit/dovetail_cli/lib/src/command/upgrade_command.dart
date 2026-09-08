import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_cli/src/config/pubspec_version.dart';
import 'package:dovetail_cli/src/sdk/sdk_locator.dart';
import 'package:dovetail_cli/src/sdk/sdk_overrides.dart';
import 'package:path/path.dart' as p;

/// Re-aponta o `pubspec_overrides.yaml` do app para o SDK preferido — o
/// comando que fecha a distância que o `doctor` só reporta: um app cujo
/// override aponta para uma versão mais velha que a instalada.
final class UpgradeCommand extends Command<int> {
  UpgradeCommand({this._sdkLocator}) {
    argParser
      ..addOption('root', help: 'the project directory; defaults to the cwd')
      ..addFlag(
        'check',
        negatable: false,
        help:
            'after re-pointing, run dart pub get and refuse if it does not '
            'resolve',
      );
  }

  final SdkLocator? _sdkLocator;

  @override
  String get name => 'upgrade';

  @override
  String get description =>
      "Re-points this app's pubspec_overrides.yaml at the installed SDK.";

  @override
  Future<int> run() async {
    final String root = argResults?.option('root') ?? Directory.current.path;

    if (!File(p.join(root, PubspecVersion.fileName)).existsSync()) {
      throw UsageException(
        'no ${PubspecVersion.fileName} in $root.',
        'dovetail upgrade re-points the overrides of a project, so it has to '
            'be run from the project root, or pointed at it with --root.\n\n$usage',
      );
    }

    final SdkInstall sdk = SdkOverrides.requireSdk(
      _sdkLocator ?? SdkLocator(),
      usage,
    );

    final File target = File(p.join(root, SdkOverrides.fileName));
    final String oldVersion = _readVersion(target);
    target.writeAsStringSync(SdkOverrides.render(sdk));

    stdout.writeln('wrote ${target.path}');
    if (oldVersion != 'none' && oldVersion != sdk.version) {
      stdout.writeln('  $oldVersion → ${sdk.version}');
    }
    stdout.writeln('  the runtime resolves from the SDK at ${sdk.packagesDir}');

    if (argResults?.flag('check') ?? false) {
      _checkResolves(root);
      stdout.writeln('  dart pub get closed: the overrides resolve');
    }
    return 0;
  }

  /// Prova o que o `upgrade` re-apontou: roda `dart pub get` no projeto e
  /// recusa se ele não fecha. A recusa nomeia a saída do pub.
  ///
  /// Usa `dart pub get` simples, não `--enforce-lockfile`. O
  /// `--enforce-lockfile` recusa quando não há `pubspec.lock` **e** quando o
  /// lockfile fica atrás — e re-apontar é exatamente o que deixa o lockfile
  /// para trás, então ele falharia em todo upgrade de verdade. O que a
  /// aceitação pede é "re-apontou E o pub get fecha", e isso é o `pub get`
  /// simples: resolve (criando o lockfile se faltar) e falha quando a
  /// dependência não existe.
  void _checkResolves(String root) {
    final ProcessResult result;
    try {
      result = Process.runSync('dart', <String>[
        'pub',
        'get',
      ], workingDirectory: root);
    } on ProcessException catch (error) {
      throw UsageException(
        'pub get failed after re-pointing',
        'dart could not be run here ($error), so the re-pointed overrides '
            'were not proven to resolve.\n\n$usage',
      );
    }

    if (result.exitCode != 0) {
      throw UsageException(
        'pub get failed after re-pointing',
        'dart pub get did not resolve $root (exit ${result.exitCode}):\n'
            '${_tailOf('${result.stdout}${result.stderr}')}\n\n$usage',
      );
    }
  }

  /// O fim legível da saída do pub — as últimas linhas não vazias — para a
  /// recusa nomear o motivo em vez de despejar o buffer inteiro.
  static String _tailOf(String output) {
    final List<String> lines = output
        .split('\n')
        .map((String line) => line.trimRight())
        .where((String line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return '(dart pub get printed nothing)';
    }
    final int from = lines.length <= 8 ? 0 : lines.length - 8;
    return lines.sublist(from).join('\n');
  }

  static final RegExp _versionPattern = RegExp(r'sdk/([^/]+)/packages');

  /// A versão a que o override atual aponta, lida do primeiro
  /// `sdk/<versão>/packages` no arquivo — 'none' quando o arquivo não existe
  /// ou não aponta para SDK nenhum.
  String _readVersion(File target) {
    if (!target.existsSync()) {
      return 'none';
    }
    final Match? match = _versionPattern.firstMatch(target.readAsStringSync());
    return match?.group(1) ?? 'none';
  }
}
