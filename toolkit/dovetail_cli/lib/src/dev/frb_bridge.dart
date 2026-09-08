import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// A bridge between a Rust crate and generated Dart, described by a
/// `flutter_rust_bridge.yaml`. The command that watches it (`dovetail dev`)
/// needs to answer one question before anything else: is the generated Dart
/// behind the Rust that generates it? And when it is, which methods are
/// missing? This file answers both by running the real codegen against a
/// scratch output — never by parsing Rust by hand.
final class FrbBridge {
  FrbBridge._({
    required this.root,
    required this.rustRoot,
    required this.dartOutput,
  });

  /// The directory holding `flutter_rust_bridge.yaml`.
  final String root;

  /// Where the crate lives, relative to [root] (the yaml's `rust_root`).
  final String rustRoot;

  /// Where generated Dart lives, relative to [root] (the yaml's `dart_output`).
  final String dartOutput;

  static const String fileName = 'flutter_rust_bridge.yaml';

  /// Walks up from [from] looking for the bridge config, like the dovetail
  /// config locator does for its own file.
  static FrbBridge? find({String? from}) {
    Directory here = Directory(from ?? Directory.current.path).absolute;
    for (int step = 0; step < 12; step++) {
      final File candidate = File(p.join(here.path, fileName));
      if (candidate.existsSync()) {
        return parse(candidate.readAsStringSync(), origin: candidate.path);
      }
      final Directory parent = here.parent;
      if (parent.path == here.path) {
        return null;
      }
      here = parent;
    }
    return null;
  }

  static FrbBridge parse(String source, {required String origin}) {
    final Object? document = loadYaml(source);
    if (document is! YamlMap) {
      throw FormatException('$origin does not hold a mapping');
    }
    final Object? rustRoot = document['rust_root'];
    final Object? dartOutput = document['dart_output'];
    if (rustRoot is! String || dartOutput is! String) {
      throw FormatException(
        '$origin needs rust_root and dart_output (strings)',
      );
    }
    final String root = p.dirname(origin);
    return FrbBridge._(root: root, rustRoot: rustRoot, dartOutput: dartOutput);
  }

  String get _generatedDartDir => p.join(root, dartOutput);

  String get _rustApiDir => p.join(root, rustRoot, 'src', 'api');

  String get _codegen => 'flutter_rust_bridge_codegen';

  bool get codegenAvailable =>
      Process.runSync('which', <String>[_codegen]).exitCode == 0;

  /// Method names the CURRENT generated Dart exposes, from the `debugName`
  /// markers the codegen writes. Parsing those beats parsing Dart by hand:
  /// the marker is the codegen's own spelling of each method.
  Set<String> currentMethodNames() => _debugNamesUnder(_generatedDartDir);

  /// Generates into a scratch directory inside [root] — the codegen refuses
  /// a dart_output with no pubspec above it, and a sibling dir under the same
  /// package is the smallest thing that satisfies it — then returns the
  /// method names the Rust WOULD generate. The tree is left untouched: the
  /// scratch config points the Dart output away from the real one, and the
  /// Rust output goes to a name that collides with nothing and is deleted
  /// afterwards. (The codegen derives the module path from the Rust output
  /// location, so that output has to live under the crate's src/ — pointing
  /// it outside fails with "prefix not found".)
  Set<String> freshMethodNames() {
    final Directory scratch = Directory(p.join(root, '.dovetail_frb_check'))
      ..createSync(recursive: true);
    final String scratchRustOutput = p.join(
      rustRoot,
      'src',
      'frb_check_generated.rs',
    );
    // Absolute first: p.relative against a relative path resolves it against
    // the process cwd, which is not [root] — the derived yaml would point at
    // a path that exists only in the caller's imagination.
    final File config = File(p.join(root, 'flutter_rust_bridge.check.yaml'))
      ..writeAsStringSync(
        'rust_input: crate::api\n'
        'rust_root: ${p.relative(p.absolute(p.join(root, rustRoot)), from: root)}\n'
        'dart_output: ${p.relative(p.join(scratch.path, 'out'), from: root)}\n'
        'rust_output: ${p.relative(p.join(root, scratchRustOutput), from: root)}\n'
        'auto_upgrade_dependency: false\n'
        'add_mod_to_lib: false\n',
      );
    try {
      final ProcessResult ran = Process.runSync(_codegen, <String>[
        'generate',
        '--config-file',
        p.basename(config.path),
      ], workingDirectory: root);
      if (ran.exitCode != 0) {
        throw ProcessException(
          _codegen,
          <String>['generate'],
          '${ran.stderr}\n${ran.stdout}',
          ran.exitCode,
        );
      }
      return _debugNamesUnder(p.join(scratch.path, 'out'));
    } finally {
      config.deleteSync();
      scratch.deleteSync(recursive: true);
      final File leftover = File(p.join(root, scratchRustOutput));
      if (leftover.existsSync()) {
        leftover.deleteSync();
      }
    }
  }

  /// The methods the Rust has that the generated Dart does not — the bridge
  /// being behind, named. Empty means the bridge is current.
  List<String> missingMethods() {
    final Set<String> fresh = freshMethodNames();
    final Set<String> current = currentMethodNames();

    // Um conjunto vazio nao e "nada faltando": e a checagem nao tendo lido
    // nada. `fresh.difference(current)` sobre um `fresh` vazio devolve vazio,
    // que este comando reporta como "the bridge is current" — o modo de falha
    // e VERDE. Qualquer coisa que quebre a leitura do marcador (a grafia das
    // aspas, um scratch que nao gerou, o codegen mudando de formato) passaria
    // por sucesso. Um check que devolve verde por nao ter conseguido olhar e
    // pior do que um check ausente, porque alguem confia nele.
    if (fresh.isEmpty) {
      throw StateError(
        'the codegen produced no method at all, so nothing could be compared. '
        'This is the check failing to look, not the bridge being current — '
        'the scratch output is at a temporary directory and the marker this '
        'reads is `debugName:`.',
      );
    }
    return (fresh.difference(current)).toList()..sort();
  }

  /// Runs the real codegen in place, so the generated Dart catches up.
  void regenerate() {
    final ProcessResult ran = Process.runSync(_codegen, <String>[
      'generate',
    ], workingDirectory: root);
    if (ran.exitCode != 0) {
      throw ProcessException(
        _codegen,
        <String>['generate'],
        '${ran.stderr}\n${ran.stdout}',
        ran.exitCode,
      );
    }
  }

  /// The rust files under the api dir, for the watcher to observe.
  List<File> rustSources() => Directory(_rustApiDir)
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((File file) => file.path.endsWith('.rs'))
      .toList();

  Set<String> _debugNamesUnder(String directory) {
    final Directory dir = Directory(directory);
    if (!dir.existsSync()) {
      return <String>{};
    }
    // As duas formas de aspas, por precaucao e nao por defeito observado.
    //
    // Medido em 2026-09-06: o codegen escreve `debugName: "..."` (61 ocorrencias
    // no bridge do produto, zero com aspas simples), e a checagem funciona —
    // um metodo novo em `api/handle.rs` sem regenerar produz "the bridge is
    // behind the Rust ... zz_probe_stale_check". O que se prende aqui e que a
    // grafia das aspas do codegen NAO e contrato: um `dart format` com
    // `prefer_single_quotes` sobre a saida, ou uma versao do gerador que mude
    // de ideia, deixaria a regex sem casar nada — e o modo de falha dessa
    // cegueira e verde, nao vermelho. Dai tambem a guarda em `missingMethods`.
    final RegExp marker = RegExp('''debugName: (?:"([^"]+)"|'([^']+)')''');
    final Set<String> names = <String>{};
    for (final FileSystemEntity entity in dir.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      for (final RegExpMatch match in marker.allMatches(
        entity.readAsStringSync(),
      )) {
        names.add(match.group(1) ?? match.group(2)!);
      }
    }
    return names;
  }

  @override
  String toString() => 'FrbBridge(${p.relative(root)})';
}

/// Snapshot of a bridge's rust sources, to tell "nothing changed" from
/// "changed" without re-reading everything on every tick.
final class RustSnapshot {
  RustSnapshot(this.files);

  factory RustSnapshot.of(FrbBridge bridge) => RustSnapshot(<String, DateTime>{
    for (final File file in bridge.rustSources())
      file.path: file.lastModifiedSync(),
  });

  final Map<String, DateTime> files;

  bool sameAs(RustSnapshot other) {
    if (files.length != other.files.length) {
      return false;
    }
    for (final MapEntry<String, DateTime> entry in files.entries) {
      final DateTime? theirs = other.files[entry.key];
      if (theirs == null || theirs != entry.value) {
        return false;
      }
    }
    return true;
  }
}

/// The line the watcher prints when a regeneration adds methods, so the
/// developer sees the bridge catching up instead of a silent success.
String regenerationNote(List<String> before, List<String> after) {
  final List<String> entered = after
      .where((String name) => !before.contains(name))
      .toList();
  if (entered.isEmpty) {
    return 'bridge regenerated';
  }
  return 'bridge regenerated: ${entered.join(', ')} entered';
}
