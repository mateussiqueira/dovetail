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

/// Every file a package carries, not only the source it ships.
///
/// `_sourceUnder` answers a narrow question — does the code we publish name
/// the product — and it is right to stay narrow: a README that says "a VPN
/// client cannot open a tunnel from its GUI process" is explaining why the
/// package exists, and forbidding that sentence would forbid the
/// documentation.
///
/// The product's own NAME is the other kind of word, and it needed the other
/// kind of scan. It was sitting in four files no glob here reached — two test
/// fixtures, a shell probe and an architecture note — as a deep link nobody
/// had a reason to spell that way. A fixture is published too.
Iterable<File> _everyTextFileUnder(Directory toolkit) sync* {
  const Set<String> skipped = <String>{
    'build',
    'target',
    '.dart_tool',
    'cargokit',
    '.git',
  };
  const Set<String> binary = <String>{
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.ico',
    '.icns',
    '.pdf',
    '.zip',
    '.gz',
    '.tar',
    '.a',
    '.dylib',
    '.so',
    '.dll',
    '.exe',
    '.bin',
    '.ttf',
    '.otf',
    '.woff',
    '.woff2',
    '.lock',
  };

  Iterable<File> walk(Directory dir) sync* {
    for (final FileSystemEntity entity in dir.listSync()) {
      if (entity is Directory) {
        if (skipped.contains(p.basename(entity.path))) {
          continue;
        }
        yield* walk(entity);
      } else if (entity is File && !binary.contains(p.extension(entity.path))) {
        yield entity;
      }
    }
  }

  yield* walk(toolkit);
}

/// The product's name, which is not a domain word.
///
/// Separate from [_forbidden] because the two lists answer different
/// questions and deserve different reach. A domain word is forbidden in
/// shipped source and allowed in prose that explains the package; a name
/// identifies one company's product and is never explaining anything.
const String _productName = 'myid';

/// The file that has to write the words in order to forbid them.
const String _thisTest = 'toolkit_purity_test.dart';

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
      expect(_forbidden, contains(_productName));
    });

    test('no file at all should carry the product name, fixtures included', () {
      final List<String> found = <String>[];
      for (final File file in _everyTextFileUnder(toolkit)) {
        if (p.basename(file.path) == _thisTest) {
          continue;
        }
        final String text = file.readAsStringSync().toLowerCase();
        if (text.contains(_productName)) {
          found.add(p.relative(file.path, from: toolkit.parent.path));
        }
      }

      expect(
        found,
        isEmpty,
        reason:
            'a deep link spelled with the product scheme reads to a stranger '
            'as the package belonging to that product, and it reads that way '
            'from a test fixture exactly as well as from the library',
      );
    });

    test('no shipped library should carry a signing key, and no file anywhere '
        'should carry a secret one', () {
      // The key itself, not the words that name its format. A minisign public
      // key is `RW` plus fifty-four more base64 characters, and matching the
      // phrase instead reported the parser, the config help and the probe —
      // three files whose whole job is to READ a key the consumer supplies.
      final RegExp publicKey = RegExp(r'\bRW[A-Za-z0-9+/]{54}\b');
      // The exact line minisign writes at the top of a key file, and not the
      // words on their own: "the minisign secret key every installed client
      // already trusts" is help text, and `signature from minisign secret
      // key` is the comment inside every .sig. Matching the phrase instead of
      // the artefact reported seven files, all of them prose or a signature.
      final RegExp secretKey = RegExp(
        r'untrusted comment:\s*minisign encrypted secret key',
        caseSensitive: false,
      );

      final List<String> shipped = <String>[];
      final List<String> secrets = <String>[];

      for (final File file in _everyTextFileUnder(toolkit)) {
        if (p.basename(file.path) == _thisTest) {
          continue;
        }
        final String text = file.readAsStringSync();
        final String where = p.relative(file.path, from: toolkit.parent.path);
        if (secretKey.hasMatch(text)) {
          secrets.add(where);
        }
        if (publicKey.hasMatch(text) &&
            (where.contains('/lib/') || where.contains('/bin/'))) {
          shipped.add(where);
        }
      }

      expect(
        secrets,
        isEmpty,
        reason:
            'the half of a signing pair that signs must never reach a '
            'repository, and a check that waits for the publication step is a '
            'check that runs after the mistake',
      );
      expect(
        shipped,
        isEmpty,
        reason:
            'the key an app trusts belongs to whoever ships that app. A '
            'toolkit that hardcodes one in what it publishes hands every '
            'consumer somebody else\'s trust root — and the private tree '
            'still carries that exact mistake in a release command',
      );
    });
  });
}
