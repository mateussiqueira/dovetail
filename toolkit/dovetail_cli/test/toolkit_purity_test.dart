import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

const List<String> _forbidden = <String>[
  'vpn',
  'tunnel',
  'reseller',
  'myid',
  'wireguard',
  'killswitch',
];

/// The toolkit tree, or a thrown error — never null.
///
/// This is the only guardian of the rule the whole directory layout exists to
/// express, and it used to walk up from the process cwd and return null when
/// it found nothing, which the test then reported as a skip. So the one run
/// where another suite had parked the cwd elsewhere was also the run where a
/// leaked product name would pass unnoticed, in green.
Directory _toolkitRoot() => Directory(p.join(repoRoot(), 'toolkit'));

Iterable<File> _sourceUnder(Directory toolkit) sync* {
  for (final FileSystemEntity package in toolkit.listSync()) {
    if (package is! Directory) {
      continue;
    }
    for (final String area in <String>['lib', 'bin']) {
      final Directory scope = Directory(p.join(package.path, area));
      if (!scope.existsSync()) {
        continue;
      }
      for (final FileSystemEntity entity in scope.listSync(recursive: true)) {
        if (entity is File && p.extension(entity.path) == '.dart') {
          yield entity;
        }
      }
    }
  }

  for (final FileSystemEntity package in toolkit.listSync()) {
    if (package is! Directory) {
      continue;
    }
    final Directory rust = Directory(p.join(package.path, 'rust', 'src'));
    if (!rust.existsSync()) {
      continue;
    }
    for (final FileSystemEntity entity in rust.listSync(recursive: true)) {
      if (entity is File && p.extension(entity.path) == '.rs') {
        yield entity;
      }
    }
  }
}

void main() {
  group('nothing in toolkit knows what this product is', () {
    late Directory toolkit;

    setUp(() => toolkit = _toolkitRoot());

    test('no source file should name the product or its domain', () {
      final Map<String, List<String>> found = <String, List<String>>{};
      for (final File file in _sourceUnder(toolkit)) {
        final String text = file.readAsStringSync().toLowerCase();
        for (final String word in _forbidden) {
          if (text.contains(word)) {
            found
                .putIfAbsent(
                  p.relative(file.path, from: toolkit.parent.path),
                  () => <String>[],
                )
                .add(word);
          }
        }
      }

      expect(
        found,
        isEmpty,
        reason:
            'a toolkit package that names the product cannot be reused by the '
            'next one, and the file path is where that rule is written',
      );
    });

    test('reading as text should be what catches it, not the shell', () {
      final Directory scratch = Directory.systemTemp.createTempSync('purity');
      addTearDown(() => scratch.deleteSync(recursive: true));

      final File tainted = File(p.join(scratch.path, 'tainted.dart'))
        ..writeAsBytesSync(<int>[...'const x = "myid";'.codeUnits, 0, 10]);

      expect(
        tainted.readAsStringSync().toLowerCase().contains('myid'),
        true,
        reason:
            'grep skips a file it classifies as data, so the invariant was '
            'blind to exactly the file that carried a raw NUL — reading the '
            'bytes as text is what makes the check honest',
      );
    });

    test('the invariant covers shipped code, not the fixtures tests use', () {
      final Iterable<String> scanned = _sourceUnder(
        toolkit,
      ).map((File file) => p.relative(file.path, from: toolkit.path));

      expect(
        scanned.any((String path) => path.contains('/test/')),
        false,
        reason:
            'a test naming the real product path on this machine is a '
            'portability question, handled by skipping; reusability is about '
            'what the package ships',
      );
      expect(scanned.any((String path) => path.contains('/lib/')), true);
    });

    test('the forbidden list should cover the words the product uses', () {
      expect(_forbidden, contains('vpn'));
      expect(_forbidden, contains('tunnel'));
      expect(_forbidden, contains('reseller'));
      expect(_forbidden, contains('myid'));
    });
  });
}
