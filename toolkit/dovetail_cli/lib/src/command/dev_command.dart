import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_cli/src/dev/frb_bridge.dart';

/// The trap this command closes is named in two documents: you add a method
/// in Rust, everything compiles, and it simply does not exist on the Dart
/// side — no error anywhere, until `verify frb` runs. `tauri dev` is weak
/// exactly here: it recompiles everything and reloads the webview, while the
/// stale bridge sails through. This command makes the bridge's state the
/// first thing it says.
///
/// Running it in a bridge package (one with a `flutter_rust_bridge.yaml`):
/// - if the generated Dart is behind the Rust, it refuses to start and names
///   each method the Dart is missing — because starting a dev session over a
///   stale bridge is how the missing method is discovered an hour later;
/// - once the bridge is current, it watches the crate and regenerates on
///   every change, saying which methods entered.
///
/// `--check` runs only the refusal, without the watch — the mode a script or
/// a test can call. `--once` runs one watch iteration (regenerate if the
/// crate changed since the last snapshot) and exits — the unit the watch
/// loop is made of, and the mode a test can observe.
final class DevCommand extends Command<int> {
  DevCommand({this._bridge}) {
    argParser
      ..addOption('root', help: 'the project directory; defaults to the cwd')
      ..addFlag(
        'check',
        negatable: false,
        help: 'only report staleness; never watch',
      )
      ..addFlag(
        'once',
        negatable: false,
        help: 'one watch iteration, then exit',
      )
      ..addOption(
        'watch-interval-ms',
        help: 'polling interval for tests; defaults to 1000',
      );
  }

  final FrbBridge? _bridge;

  @override
  String get name => 'dev';

  @override
  String get description =>
      'Keeps the Dart side of a flutter_rust_bridge crate current while you '
      'edit Rust.';

  @override
  Future<int> run() async {
    final String root = argResults?.option('root') ?? Directory.current.path;
    FrbBridge? bridge = _bridge;
    bridge ??= FrbBridge.find(from: root);
    if (bridge == null) {
      throw UsageException(
        'no ${FrbBridge.fileName} was found here or in any parent '
            'directory.',
        'dev watches a flutter_rust_bridge crate, which is described by '
            'that file. Run it inside the bridge package, or point --root at '
            'it.\n\n$usage',
      );
    }

    if (!bridge.codegenAvailable) {
      stderr.writeln(
        'flutter_rust_bridge_codegen is not installed. Install the pinned '
        'version: cargo install flutter_rust_bridge_codegen '
        '--version <pin from rust/Cargo.toml>',
      );
      return 1;
    }

    stdout.writeln('── checking the bridge in $root ──');
    if (argResults?.flag('once') ?? false) {
      // --once IS the remedy for a stale bridge: regenerate and report what
      // entered. Refusing here would make the fix unreachable from this
      // command.
      return _oneIteration(bridge);
    }

    final List<String> missing = bridge.missingMethods();
    if (missing.isNotEmpty) {
      stderr.writeln(
        'the bridge is behind the Rust. The Dart side is '
        'missing:',
      );
      for (final String method in missing) {
        stderr.writeln('  $method');
      }
      stderr.writeln(
        'A dev session over this bridge would compile and run without these '
        'methods — which is the exact trap. Regenerate first: '
        'dovetail dev --once (in $root)',
      );
      return 1;
    }

    if (argResults?.flag('check') ?? false) {
      stdout.writeln('the bridge is current');
      return 0;
    }

    return _watch(bridge);
  }

  /// What the watch does when it notices a change: regenerate, then report
  /// what entered. Callable on its own so a test can observe the bridge
  /// catching up after editing a .rs.
  Future<int> _oneIteration(FrbBridge bridge) async {
    final Set<String> before = bridge.currentMethodNames();
    bridge.regenerate();
    final Set<String> after = bridge.currentMethodNames();
    stdout.writeln(regenerationNote(before.toList(), after.toList()));
    return 0;
  }

  Future<int> _watch(FrbBridge bridge) async {
    final int intervalMs =
        int.tryParse(argResults?.option('watch-interval-ms') ?? '') ?? 1000;
    stdout.writeln(
      'watching ${bridge.rustRoot} — edit a .rs and the bridge '
      'regenerates. Ctrl-C to stop.',
    );

    RustSnapshot last = RustSnapshot.of(bridge);
    Set<String> lastNames = bridge.currentMethodNames();

    while (true) {
      await Future<void>.delayed(Duration(milliseconds: intervalMs));
      final RustSnapshot now = RustSnapshot.of(bridge);
      if (now.sameAs(last)) {
        continue;
      }
      last = now;
      bridge.regenerate();
      final Set<String> names = bridge.currentMethodNames();
      stdout.writeln(regenerationNote(lastNames.toList(), names.toList()));
      lastNames = names;
    }
  }
}
