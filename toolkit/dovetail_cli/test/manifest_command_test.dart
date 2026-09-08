import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _referenceSignature = '''
untrusted comment: signature from minisign secret key
RUQhww+7hfwEkWtARB009cGoM/E5aak5XOvFMIgz6fLcTBlqcBJONzflPABPaAHxnlx5ojvkzJy/zAkxwxHM+kORnis2FsJ2ygw=
trusted comment: timestamp:1788272466\tfile:small.bin\thashed
pMYx41+3aH2fe3X6jQwLD58C1SBja+rh0FHO+knc/CQedUvUQQhIR7i/l0Ra1N2Djrjm/6XRfpzmnQbF13BGBw==
''';

void main() {
  late Directory root;
  late String signaturePath;
  late CommandRunner<int> runner;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_manifest');
    signaturePath = p.join(root.path, 'app.tar.gz.minisig');
    File(signaturePath).writeAsStringSync(_referenceSignature);
    runner = CommandRunner<int>('dovetail', 'test')
      ..addCommand(ManifestCommand());
  });

  tearDown(() => root.deleteSync(recursive: true));

  String outPath() => p.join(root.path, 'latest.json');

  test('should embed the content of the signature, not its path', () async {
    await runner.run(<String>[
      'manifest',
      '--version',
      '2.1.0',
      '--release',
      'darwin-aarch64=https://cdn/app.tar.gz=$signaturePath',
      '--out',
      outPath(),
    ]);

    final Map<String, Object?> written =
        jsonDecode(File(outPath()).readAsStringSync()) as Map<String, Object?>;
    final Map<String, Object?> platforms =
        written['platforms']! as Map<String, Object?>;
    final Map<String, Object?> release =
        platforms['darwin-aarch64']! as Map<String, Object?>;

    // base64 first, with no fallback, because that is all a client in the
    // field does before it parses. Reading this through MinisignSignature
    // would accept the raw text too, and accepting both is what let the
    // command write the form no client reads.
    final String decoded = utf8.decode(
      base64.decode(release['signature']! as String),
    );

    expect(decoded, _referenceSignature);
    expect(release['signature'], isNot(contains(signaturePath)));
    expect(
      release['signature'],
      isNot(contains('untrusted comment:')),
      reason: 'the field is base64 around the text, never the text itself',
    );
  });

  test('what the CLI writes should be readable by the updater', () async {
    await runner.run(<String>[
      'manifest',
      '--version',
      '2.1.0',
      '--release',
      'darwin-aarch64=https://cdn/app.tar.gz=$signaturePath',
      '--out',
      outPath(),
    ]);

    final UpdateManifest manifest = ManifestParser.parse(
      File(outPath()).readAsStringSync(),
    );

    expect(manifest.version, Version.parse('2.1.0'));
    expect(
      MinisignSignature.parse(
        manifest.releaseFor('darwin-aarch64').signature,
      ).keyIdHex,
      '9104FC85BB0FC321',
    );
    expect(
      const UpdatePolicy()
          .decide(installed: Version.parse('2.0.0'), manifest: manifest)
          .shouldUpdate,
      true,
    );
  });

  test('should carry every platform it was given', () async {
    await runner.run(<String>[
      'manifest',
      '--version',
      '3.0.0',
      '--release',
      'darwin-aarch64=https://cdn/a=$signaturePath',
      '--release',
      'windows-x86_64=https://cdn/b=$signaturePath',
      '--release',
      'linux-x86_64=https://cdn/c=$signaturePath',
      '--out',
      outPath(),
    ]);

    expect(
      ManifestParser.parse(File(outPath()).readAsStringSync()).releases.keys,
      hasLength(3),
    );
  });

  test('should refuse a release with no signature file on disk', () async {
    await expectLater(
      runner.run(<String>[
        'manifest',
        '--version',
        '1.0.0',
        '--release',
        'darwin-aarch64=https://cdn/a=${p.join(root.path, 'absent.sig')}',
        '--out',
        outPath(),
      ]),
      throwsA(isA<UsageException>()),
    );
  });

  test('should refuse a release that is not three parts', () async {
    await expectLater(
      runner.run(<String>[
        'manifest',
        '--version',
        '1.0.0',
        '--release',
        'darwin-aarch64=https://cdn/a',
        '--out',
        outPath(),
      ]),
      throwsA(isA<UsageException>()),
    );
  });

  test('should refuse to write a manifest with no release at all', () async {
    await expectLater(
      runner.run(<String>[
        'manifest',
        '--version',
        '1.0.0',
        '--out',
        outPath(),
      ]),
      throwsA(isA<UsageException>()),
    );
  });
}
