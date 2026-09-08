import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The fixture is a REAL flutter_rust_bridge project, and the test drives the
/// REAL codegen through the REAL command: the whole point of `dev` is to say
/// "the bridge is behind" when it is, and the only honest way to know that is
/// to generate and compare. These tests need `flutter_rust_bridge_codegen`
/// on the PATH; they skip with the reason written when it is not.
void main() {
  late Directory root;

  final String entryPoint = p.join(
    Directory.current.path,
    'bin',
    'dovetail.dart',
  );

  final bool haveCodegen =
      Process.runSync('which', <String>[
        'flutter_rust_bridge_codegen',
      ]).exitCode ==
      0;

  setUp(() => root = Directory.systemTemp.createTempSync('dovetail_dev'));

  tearDown(() => root.deleteSync(recursive: true));

  void writeFile(String relative, String content) {
    final File file = File(p.join(root.path, relative))
      ..parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  /// A minimal but real bridge package: a crate with one api method and the
  /// frb config that generates Dart from it. `add_mod_to_lib: false` keeps
  /// the codegen from editing lib.rs during checks, and
  /// `auto_upgrade_dependency: false` keeps it from touching the pubspec.
  void bridgeProject({String? extraApi}) {
    writeFile(
      'pubspec.yaml',
      'name: frb_fixture\nenvironment:\n  sdk: ^3.12.2\n',
    );
    writeFile(
      'rust/Cargo.toml',
      '[package]\n'
          'name = "frb_fixture"\n'
          'version = "0.1.0"\n'
          'edition = "2021"\n'
          'license = "MIT"\n'
          '[lib]\n'
          'crate-type = ["cdylib", "staticlib", "lib"]\n'
          '[dependencies]\n'
          'flutter_rust_bridge = "=2.13.0"\n',
    );
    writeFile('rust/src/lib.rs', 'pub mod api;\npub mod frb_generated;\n');
    writeFile(
      'rust/src/api/mod.rs',
      'pub fn alpha() -> String {\n  "a".into()\n}\n${extraApi ?? ''}',
    );
    writeFile(
      'flutter_rust_bridge.yaml',
      'rust_input: crate::api\n'
          'rust_root: rust/\n'
          'dart_output: lib/src/rust\n'
          'auto_upgrade_dependency: false\n'
          'add_mod_to_lib: false\n',
    );
  }

  /// Runs the real codegen once so the fixture starts in the clean state a
  /// real checkout would be in.
  void generateOnce() {
    final ProcessResult ran = Process.runSync(
      'flutter_rust_bridge_codegen',
      <String>['generate'],
      workingDirectory: root.path,
    );
    expect(ran.exitCode, 0, reason: ran.stderr.toString());
  }

  ProcessResult dev(List<String> extra) => Process.runSync('dart', <String>[
    'run',
    entryPoint,
    'dev',
    '--root',
    root.path,
    ...extra,
  ], workingDirectory: root.path);

  group('with a real bridge fixture', () {
    test(
      'check should refuse when the Dart is behind, naming the method',
      () {
        if (!haveCodegen) {
          markTestSkipped('flutter_rust_bridge_codegen is not installed');
          return;
        }
        bridgeProject();
        generateOnce();

        // The bridge is current: a fresh generation adds nothing.
        final ProcessResult clean = dev(<String>['--check']);
        expect(clean.exitCode, 0, reason: clean.stderr.toString());

        // Add a Rust method WITHOUT regenerating — the exact trap `dev`
        // exists to catch. The command must refuse and name the method.
        writeFile(
          'rust/src/api/mod.rs',
          'pub fn alpha() -> String {\n  "a".into()\n}\n'
              'pub fn novo_metodo() -> String {\n  "novo".into()\n}\n',
        );
        final ProcessResult dirty = dev(<String>['--check']);
        expect(dirty.exitCode, isNot(0));
        expect(
          '${dirty.stdout}${dirty.stderr}',
          contains('novo_metodo'),
          reason: 'the refusal must name the missing method',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'editing a .rs should regenerate the .dart and name what entered',
      () {
        if (!haveCodegen) {
          markTestSkipped('flutter_rust_bridge_codegen is not installed');
          return;
        }
        bridgeProject();
        generateOnce();

        expect(
          generatedDart(root.path),
          contains('alpha'),
          reason: 'the fixture starts with the bridge generated',
        );

        // The developer edits the Rust side. The watch would notice and
        // regenerate; `--once` is that same body callable on its own, so the
        // test can observe the bridge catching up.
        writeFile(
          'rust/src/api/mod.rs',
          'pub fn alpha() -> String {\n  "a".into()\n}\n'
              'pub fn segundo_metodo() -> String {\n  "b".into()\n}\n',
        );

        final ProcessResult once = dev(<String>['--once']);
        expect(once.exitCode, 0, reason: once.stderr.toString());
        expect(
          generatedDart(root.path),
          contains('segundo_metodo'),
          reason: 'editing a .rs must regenerate the .dart',
        );
        expect(
          '${once.stdout}${once.stderr}',
          contains('segundo_metodo'),
          reason: 'the regeneration must name what entered',
        );

        // And now the bridge is current again.
        final ProcessResult clean = dev(<String>['--check']);
        expect(clean.exitCode, 0, reason: clean.stderr.toString());
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}

/// All generated Dart under [root]/lib/src/rust, concatenated — the codegen
/// may put a method in api.dart or in frb_generated.dart depending on the
/// module structure, and the bridge's own staleness check reads the whole
/// tree, so the test should too.
String generatedDart(String root) {
  final Directory generated = Directory(p.join(root, 'lib', 'src', 'rust'));
  final StringBuffer all = StringBuffer();
  for (final FileSystemEntity entity in generated.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File && entity.path.endsWith('.dart')) {
      all.writeln(entity.readAsStringSync());
    }
  }
  return all.toString();
}
