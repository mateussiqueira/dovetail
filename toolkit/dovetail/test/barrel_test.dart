import 'dart:io';

import 'package:dovetail/dovetail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const List<String> _reexported = <String>[
  'dovetail_form_validation',
  'dovetail_platform_channel',
  'dovetail_process_runner',
  'dovetail_rust_core',
  'dovetail_shortcut_channel',
  'dovetail_updater',
];

File _barrel() => File(p.join(Directory.current.path, 'lib', 'dovetail.dart'));

void main() {
  group('what one dependency has to bring', () {
    test('a type from each runtime package should resolve', () {
      expect(SingleInstanceVerdict.values, isNotEmpty);
      expect(ShortcutBackend.values, isNotEmpty);
      expect(UpdateOs.values, isNotEmpty);
      expect(const SystemProcessRunner(), isA<ProcessRunner>());
      expect(const RequiredField('x'), isA<FieldValidation>());
      expect(RustBridge, isNotNull);
    });

    test('the barrel should name every runtime package, and only those', () {
      final List<String> exported = _barrel()
          .readAsLinesSync()
          .where((String line) => line.startsWith('export '))
          .map((String line) => line.split('package:')[1].split('/').first)
          .toList();

      expect(exported..sort(), _reexported);
    });

    test('it should not reach the packages that only run in the pipeline', () {
      final String source = _barrel().readAsStringSync();

      for (final String buildTime in <String>[
        'dovetail_bundler',
        'dovetail_signer',
        'dovetail_cli',
      ]) {
        expect(
          source,
          isNot(contains(buildTime)),
          reason:
              'bundling and signing happen on a release machine, never inside '
              'the shipped app, and pulling them in would put a code-signing '
              'toolchain in every user build',
        );
      }
    });

    test('the pubspec should depend on exactly what the barrel exports', () {
      final List<String> declared =
          File(p.join(Directory.current.path, 'pubspec.yaml'))
              .readAsLinesSync()
              .map((String line) => line.trimRight())
              .where((String line) => line.startsWith('  dovetail_'))
              .map((String line) => line.split(':').first.trim())
              .toList();

      expect(declared..sort(), _reexported);
    });

    test('the local overrides should cover every package it declares', () {
      // O override e o que faz `dart pub get` resolver sem o pub.dev. Se um
      // pacote entra no pubspec e ninguem acrescenta o caminho aqui, o clone
      // de quem chegou hoje tenta baixar uma versao que talvez nao exista.
      final File overrides = File(
        p.join(Directory.current.path, 'pubspec_overrides.yaml'),
      );
      final List<String> local = overrides
          .readAsLinesSync()
          .map((String line) => line.trimRight())
          .where((String line) => line.startsWith('  dovetail_'))
          .map((String line) => line.split(':').first.trim())
          .toList();

      expect(local..sort(), _reexported);
    });
  });

  group('the names it merges', () {
    test('no two packages should offer the same type under one import', () {
      expect(SingleInstanceVerdict.primary.mayRun, true);
      expect(UpdateOs.darwin.wireName, 'darwin');
      expect(
        PlatformKey.validate('darwin-aarch64'),
        'darwin-aarch64',
        reason:
            'the platform key vocabulary has to survive the merge, because it '
            'is what the config and the manifest both key off',
      );
    });
  });
}
