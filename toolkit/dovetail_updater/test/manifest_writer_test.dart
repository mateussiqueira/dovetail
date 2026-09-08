import 'dart:convert';

import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:test/test.dart';

const String _signature =
    'untrusted comment: signature from minisign secret key\n'
    'RUQhww+7hfwEkWtARB009cGoM/E5aak5XOvFMIgz6fLcTBlqcBJONzflPABPaAHxnlx5'
    'ojvkzJy/zAkxwxHM+kORnis2FsJ2ygw=\n'
    'trusted comment: timestamp:1788272466\tfile:small.bin\thashed\n'
    'pMYx41+3aH2fe3X6jQwLD58C1SBja+rh0FHO+knc/CQedUvUQQhIR7i/l0Ra1N2Djrjm'
    '/6XRfpzmnQbF13BGBw==\n';

ManifestEntry entryFor(
  String platformKey, {
  String url = 'https://cdn.example.com/app.tar.gz',
  String signature = _signature,
}) => ManifestEntry(platformKey: platformKey, url: url, signature: signature);

void main() {
  group('ManifestWriter', () {
    test('what it writes should be readable by the parser', () {
      final UpdateManifest manifest = ManifestParser.parse(
        ManifestWriter.render(
          version: '2.1.0',
          notes: 'kill switch nftables',
          entries: <ManifestEntry>[
            entryFor('darwin-universal'),
            entryFor('windows-x86_64'),
          ],
        ),
      );

      expect(manifest.version, Version.parse('2.1.0'));
      expect(manifest.releases.keys, hasLength(2));
    });

    test('a version the client cannot parse should be refused', () {
      expect(
        () => ManifestWriter.render(
          version: 'banana',
          entries: <ManifestEntry>[entryFor('darwin-universal')],
        ),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.remedy,
            'remedy',
            contains('no update ever arriving'),
          ),
        ),
        reason:
            'the command used to write it verbatim, producing a manifest its '
            'own parser rejects',
      );
    });

    test('a version with build metadata should survive the round trip', () {
      expect(
        ManifestParser.parse(
          ManifestWriter.render(
            version: '2.1.0+904',
            entries: <ManifestEntry>[entryFor('darwin-universal')],
          ),
        ).version,
        Version.parse('2.1.0+904'),
      );
    });

    test('the same platform twice should be refused, not overwritten', () {
      expect(
        () => ManifestWriter.render(
          version: '2.1.0',
          entries: <ManifestEntry>[
            entryFor('darwin-universal', url: 'https://cdn/a.tar.gz'),
            entryFor('darwin-universal', url: 'https://cdn/b.tar.gz'),
          ],
        ),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.remedy,
            'remedy',
            contains('silently replace'),
          ),
        ),
      );
    });

    test('an empty signature should be refused', () {
      expect(
        () => ManifestWriter.render(
          version: '2.1.0',
          entries: <ManifestEntry>[
            entryFor('darwin-universal', signature: '   '),
          ],
        ),
        throwsA(isA<UpdateFailure>()),
      );
    });

    test('a plain http url should be refused', () {
      expect(
        () => ManifestWriter.render(
          version: '2.1.0',
          entries: <ManifestEntry>[
            entryFor('darwin-universal', url: 'http://cdn/app.tar.gz'),
          ],
        ),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.remedy,
            'remedy',
            contains('which build a machine is running'),
          ),
        ),
      );
    });

    test('no platform at all should be refused', () {
      expect(
        () => ManifestWriter.render(
          version: '2.1.0',
          entries: const <ManifestEntry>[],
        ),
        throwsA(isA<UpdateFailure>()),
      );
    });

    test('blank notes should not become a notes field', () {
      expect(
        ManifestWriter.render(
          version: '2.1.0',
          notes: '   ',
          entries: <ManifestEntry>[entryFor('darwin-universal')],
        ),
        isNot(contains('"notes"')),
      );
    });

    test('the same input should render byte for byte the same', () {
      String render() => ManifestWriter.render(
        version: '2.1.0',
        entries: <ManifestEntry>[entryFor('darwin-universal')],
      );
      expect(render(), render());
    });

    test('it should end with a newline, as a file on disk should', () {
      expect(
        ManifestWriter.render(
          version: '2.1.0',
          entries: <ManifestEntry>[entryFor('darwin-universal')],
        ),
        endsWith('\n'),
      );
    });

    test('the signature field should be base64 around the minisign text', () {
      final Map<String, Object?> platform = _platformOf(
        ManifestWriter.render(
          version: '2.1.0',
          entries: <ManifestEntry>[entryFor('darwin-universal')],
        ),
        'darwin-universal',
      );

      expect(
        utf8.decode(base64.decode(platform['signature']! as String)),
        _signature,
        reason:
            'a client already in the field base64-decodes the field before it '
            'parses; the raw minisign text is a release it refuses',
      );
    });

    test('a signature handed over already wrapped should not wrap twice', () {
      final Map<String, Object?> platform = _platformOf(
        ManifestWriter.render(
          version: '2.1.0',
          entries: <ManifestEntry>[
            entryFor(
              'darwin-universal',
              signature: base64.encode(utf8.encode(_signature)),
            ),
          ],
        ),
        'darwin-universal',
      );

      expect(
        utf8.decode(base64.decode(platform['signature']! as String)),
        _signature,
        reason:
            'two layers decode to base64, not to minisign text, so the client '
            'fails at the parse rather than at the decode',
      );
    });

    test('something that is not a signature at all should be refused', () {
      expect(
        () => ManifestWriter.render(
          version: '2.1.0',
          entries: <ManifestEntry>[
            entryFor('darwin-universal', signature: 'dist/app.dmg.minisig'),
          ],
        ),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.message,
            'message',
            allOf(
              contains('darwin-universal'),
              contains('not a minisign signature'),
            ),
          ),
        ),
        reason:
            'passing the path instead of the contents used to render a '
            'manifest whose own parser then accepted the path as a signature',
      );
    });
  });
}

Map<String, Object?> _platformOf(String rendered, String platformKey) {
  final Map<String, Object?> decoded =
      jsonDecode(rendered) as Map<String, Object?>;
  final Map<String, Object?> platforms =
      decoded['platforms']! as Map<String, Object?>;
  return platforms[platformKey]! as Map<String, Object?>;
}
