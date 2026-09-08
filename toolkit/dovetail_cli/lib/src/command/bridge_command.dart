import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'package:dovetail_cli/src/bridge/bridge_from.dart';
import 'package:dovetail_cli/src/bridge/bridge_scaffold.dart';
import 'package:dovetail_cli/src/bridge/bridge_template.dart';
import 'package:dovetail_cli/src/sdk/sdk_locator.dart';

/// Gera o plugin ffiPlugin que fala com o núcleo Rust de um produto — o
/// mecanismo do qual o `product/desktop_core_bridge` é o fixture.
final class BridgeCommand extends Command<int> {
  BridgeCommand({SdkLocator? sdkLocator}) {
    addSubcommand(BridgeInitCommand(sdkLocator: sdkLocator));
  }

  @override
  String get name => 'bridge';

  @override
  String get description =>
      'Generates the FFI plugin that talks to the product Rust core.';
}

final class BridgeInitCommand extends Command<int> {
  BridgeInitCommand({this._sdkLocator}) {
    argParser
      ..addOption(
        'core',
        help:
            'path of the product crate (the directory holding its '
            'Cargo.toml)',
      )
      ..addOption(
        'name',
        help:
            'package name; letters, digits and underscores, starting with '
            'a letter',
      )
      ..addOption(
        'out',
        help:
            'directory to generate into; defaults to '
            './<name>',
      )
      ..addOption(
        'template',
        help: 'bridge template directory; defaults to the SDK template',
      )
      ..addOption(
        'from',
        help:
            'path of an existing bridge to copy the product entries from: '
            'rust/src/api/, rust/src/support.rs and the sibling-crate deps',
      );
  }

  final SdkLocator? _sdkLocator;

  @override
  String get name => 'init';

  @override
  String get description =>
      'Generates the ffiPlugin bridge from the SDK template.';

  @override
  Future<int> run() async {
    final String? nameArg = argResults?.option('name');
    final String? coreArg = argResults?.option('core');

    if (nameArg == null || nameArg.trim().isEmpty) {
      throw UsageException(
        '--name is required.',
        'The package name keys the pubspec, the podspec and the classes '
            'directory.\n\n$usage',
      );
    }
    if (coreArg == null || coreArg.trim().isEmpty) {
      throw UsageException(
        '--core is required.',
        'The bridge exists to talk to a core: the crate directory that holds '
            'its Cargo.toml.\n\n$usage',
      );
    }
    _validateName(nameArg);

    final String corePath = _corePath(coreArg);
    final String coreCrateName = _coreCrateName(corePath);
    _warnIfNoHandle(corePath);

    final String out = p.normalize(
      p.absolute(
        argResults?.option('out') ?? p.join(Directory.current.path, nameArg),
      ),
    );
    final Directory outDir = Directory(out);
    if (outDir.existsSync() && outDir.listSync().isNotEmpty) {
      throw UsageException(
        'there is already something at $out.',
        'Choose a fresh --out, or remove the directory first.\n\n$usage',
      );
    }

    final BridgeTemplate? template = BridgeTemplate.locate(
      explicit: argResults?.option('template'),
      sdkHome: _sdkLocator?.home,
    );
    if (template == null) {
      throw UsageException(
        'no bridge template found.',
        'Install the SDK first (dovetail self-install --base-url <url>), or '
            'pass --template pointing at a bridge template directory. '
            'A --template that was given but does not exist also lands here.\n\n'
            '$usage',
      );
    }

    final List<String> written = BridgeScaffold(template: template).render(
      out: out,
      name: nameArg,
      coreCrateName: coreCrateName,
      corePath: corePath,
    );

    final List<String> copied = _copyFrom(out, coreCrateName);

    stdout
      ..writeln('wrote ${outDir.path} (${written.length} files)')
      ..writeln('  core      $coreCrateName at $corePath')
      ..writeln('  dovetail_rust_core ${template.rustCoreDart}');
    if (copied.isNotEmpty) {
      stdout.writeln('  from      copied ${copied.length} files');
    }
    stdout
      ..writeln()
      ..writeln('next:')
      ..writeln('  flutter_rust_bridge_codegen generate')
      ..writeln('  cd rust && cargo check')
      ..writeln('  flutter test test/core_coverage_test.dart');
    return 0;
  }

  static final RegExp _namePattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$');

  void _validateName(String name) {
    if (!_namePattern.hasMatch(name)) {
      throw UsageException(
        '$name is not a package name.',
        'It must start with a letter and hold letters, digits and '
            'underscores only.\n\n$usage',
      );
    }
  }

  String _corePath(String given) {
    final Directory dir = Directory(p.normalize(p.absolute(given)));
    if (!dir.existsSync()) {
      throw UsageException(
        'no crate directory at ${dir.path}.',
        '--core is the directory that holds the Cargo.toml of the product '
            'crate.\n\n$usage',
      );
    }
    return dir.resolveSymbolicLinksSync();
  }

  String _coreCrateName(String corePath) {
    final File manifest = File(p.join(corePath, 'Cargo.toml'));
    if (!manifest.existsSync()) {
      throw UsageException(
        'no Cargo.toml at $corePath.',
        '--core is the crate directory, and a crate carries its manifest.\n\n'
            '$usage',
      );
    }
    final RegExpMatch? match = RegExp(
      r'\[package\][^\[]*?^name\s*=\s*"([^"]+)"',
      multiLine: true,
    ).firstMatch(manifest.readAsStringSync());
    if (match == null) {
      throw UsageException(
        'the Cargo.toml at $corePath declares no package name.',
        'The bridge depends on the crate under its real name, not a guessed '
            'one.\n\n$usage',
      );
    }
    return match.group(1)!;
  }

  /// Aviso não-fatal: sem `src/handle.rs` no core, o `core_coverage_test` —
  /// o portão de forma que o template carrega — não tem o que ler e pula.
  /// Deixar a descoberta para o teste é tarde demais; avisar aqui nomeia o
  /// que o consumidor deve conferir.
  void _warnIfNoHandle(String corePath) {
    if (!File(p.join(corePath, 'src', 'handle.rs')).existsSync()) {
      stdout.writeln(
        'note: ${p.join(corePath, 'src', 'handle.rs')} not found — the '
        'core_coverage_test reads it; add it or the portão will skip',
      );
    }
  }

  List<String> _copyFrom(String out, String coreCrateName) {
    final String? fromArg = argResults?.option('from');
    if (fromArg == null || fromArg.trim().isEmpty) {
      return <String>[];
    }
    final String fromPath = p.normalize(p.absolute(fromArg));
    final Directory fromDir = Directory(fromPath);
    if (!fromDir.existsSync()) {
      throw UsageException(
        'no existing bridge at $fromPath.',
        '--from is the directory of a bridge already generated (the one '
            'holding its rust/Cargo.toml).\n\n$usage',
      );
    }
    if (!File(p.join(fromPath, 'rust', 'Cargo.toml')).existsSync()) {
      throw UsageException(
        'no rust/Cargo.toml at $fromPath.',
        '--from must point at a generated bridge, which carries its '
            'rust/Cargo.toml.\n\n$usage',
      );
    }
    return const BridgeFrom().copy(
      from: fromPath,
      out: out,
      coreCrateName: coreCrateName,
    );
  }
}
