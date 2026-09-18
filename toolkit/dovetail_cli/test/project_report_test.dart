import 'dart:io';

import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Um daemon embarcado, com o binario que o `build` copia e nao compila.
const String _macosDaemon =
    'service:\n'
    '  macos:\n'
    '    label: com.example.demo.helper\n'
    '    program: demo-helper\n'
    '    binary: target/release/demo-helper\n';

DovetailConfig configWith({
  String targets = 'darwin-aarch64',
  String extra = '',
}) => DovetailConfig.parse('''
identifier: com.example.demo
name: Demo Client
manufacturer: Example Ltda
targets: [$targets]
$extra
''');

ProjectReport reportFor({
  DovetailConfig? config,
  String? version = '4.2.0',
  String host = 'macos',
  Map<String, String>? environment,
  String? root,
  ShipChannel channel = ShipChannel.release,
}) => ProjectReport.of(
  config: config,
  version: version,
  host: host,
  environment: environment,
  root: root,
  channel: channel,
);



ProjectNote noteOn(ProjectReport report, String subject) =>
    report.notes.firstWhere((ProjectNote note) => note.subject == subject);

void main() {
  group('a project with no config at all', () {
    test('should say only that, and point at init', () {
      final ProjectReport report = reportFor(config: null);

      expect(report.notes, hasLength(1));
      expect(report.notes.single.finding, ProjectFinding.missing);
      expect(report.notes.single.detail, contains('dovetail init'));
      expect(report.shipCanRelease, false);
    });
  });

  group('what it reads back', () {
    test('the identity fields should be shown as given', () {
      final ProjectReport report = reportFor(config: configWith());

      expect(noteOn(report, 'identifier').detail, 'com.example.demo');
      expect(
        noteOn(report, 'name').detail,
        'Demo Client by Example Ltda',
        reason: 'the manufacturer is what Add or Remove Programs shows',
      );
    });

    test('a pubspec with no version should be missing, not blank', () {
      final ProjectReport report = reportFor(
        config: configWith(),
        version: null,
      );

      expect(noteOn(report, 'version').finding, ProjectFinding.missing);
      expect(report.shipCanRelease, false);
    });
  });

  group('targets, read from the host that is asking', () {
    test('should count what this host builds against the whole matrix', () {
      final ProjectReport report = reportFor(
        config: configWith(
          targets: 'darwin-aarch64, darwin-x86_64, windows-x86_64',
        ),
      );

      expect(noteOn(report, 'targets').finding, ProjectFinding.ready);
      expect(noteOn(report, 'targets').detail, contains('of 3'));
    });

    test('a host with none of them is off, not missing', () {
      final ProjectReport report = reportFor(
        config: configWith(targets: 'windows-x86_64'),
      );

      expect(
        noteOn(report, 'targets').finding,
        ProjectFinding.notConfigured,
        reason:
            'a runner whose part of the matrix lives elsewhere is not a broken '
            'project, and calling it missing would fail a green CI job',
      );
      expect(report.shipCanRelease, true);
    });
  });

  group('what it warns about without failing', () {
    test('no update section should say installed clients learn nothing', () {
      expect(
        noteOn(reportFor(config: configWith()), 'update').detail,
        contains('learn nothing'),
      );
    });

    test('an update key with no base-url should say what that costs', () {
      final ProjectReport report = reportFor(
        config: configWith(extra: 'update:\n  key: keys/update.key\n'),
      );

      expect(noteOn(report, 'update').finding, ProjectFinding.notConfigured);
      expect(noteOn(report, 'update').detail, contains('spelled out'));
    });

    test('a full update section should be ready', () {
      final ProjectReport report = reportFor(
        config: configWith(
          extra:
              'update:\n  key: keys/update.key\n'
              '  base-url: https://cdn.example.com/r\n'
              '  public-key: |\n    untrusted comment: minisign public key D18395BE8A6B994E\n    RWROmWuKvpWD0RErEh4kcn0sjuu4dQYX5MERE9dNGuImxQXHzNuRYLVP\n',
        ),
      );

      expect(noteOn(report, 'update').finding, ProjectFinding.ready);
      expect(noteOn(report, 'update').detail, contains('cdn.example.com'));
    });

    test('an update section without the public key should be missing, '
        'naming ship', () {
      // O ship recusa sem ela; o doctor dizia `ok update` para o mesmo yaml.
      // Dois comandos discordando sobre o que pode publicar e um deles
      // mentindo.
      final ProjectReport report = reportFor(
        config: configWith(
          extra:
              'update:\n  key: keys/update.key\n'
              '  base-url: https://cdn.example.com/r\n',
        ),
      );

      expect(noteOn(report, 'update').finding, ProjectFinding.missing);
      expect(noteOn(report, 'update').detail, contains('public-key'));
      expect(noteOn(report, 'update').detail, contains('ship'));
      expect(report.shipCanRelease, false);
    });

    const String updateReady =
        'update:\n  key: keys/update.key\n'
        '  base-url: https://cdn.example.com/r\n'
        '  public-key: |\n    untrusted comment: minisign public key D18395BE8A6B994E\n    RWROmWuKvpWD0RErEh4kcn0sjuu4dQYX5MERE9dNGuImxQXHzNuRYLVP\n';

    test('an update section whose secret key is not on disk should be missing, '
        'naming the path: the release step would die after the build', () {
      final Directory root = Directory.systemTemp.createTempSync(
        'dovetail_update_key',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      final ProjectReport report = reportFor(
        config: configWith(extra: updateReady),
        root: root.path,
      );

      expect(noteOn(report, 'update').finding, ProjectFinding.missing);
      expect(noteOn(report, 'update').detail, contains('keys/update.key'));
      expect(noteOn(report, 'update').detail, contains('release step'));
      expect(report.shipCanRelease, false);
    });

    test('a key present and unencrypted should be ready', () {
      final Directory root = Directory.systemTemp.createTempSync(
        'dovetail_update_key',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      File(p.join(root.path, 'keys', 'update.key'))
        ..createSync(recursive: true)
        ..writeAsStringSync('key placeholder, never a real header\n');

      final ProjectReport report = reportFor(
        config: configWith(extra: '$updateReady  unencrypted: true\n'),
        root: root.path,
      );

      expect(noteOn(report, 'update').finding, ProjectFinding.ready);
    });

    test('an encrypted key with no password exported should be missing, naming '
        'the variable the release step refuses without', () {
      final Directory root = Directory.systemTemp.createTempSync(
        'dovetail_update_key',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      File(p.join(root.path, 'keys', 'update.key'))
        ..createSync(recursive: true)
        ..writeAsStringSync('key placeholder, never a real header\n');

      final ProjectReport report = reportFor(
        config: configWith(extra: updateReady),
        root: root.path,
        environment: const <String, String>{},
      );

      expect(noteOn(report, 'update').finding, ProjectFinding.missing);
      expect(
        noteOn(report, 'update').detail,
        contains('DOVETAIL_UPDATE_KEY_PASSWORD'),
      );
      expect(report.shipCanRelease, false);
    });

    test('the same encrypted key with the password exported should be ready', () {
      final Directory root = Directory.systemTemp.createTempSync(
        'dovetail_update_key',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      File(p.join(root.path, 'keys', 'update.key'))
        ..createSync(recursive: true)
        ..writeAsStringSync('key placeholder, never a real header\n');

      final ProjectReport report = reportFor(
        config: configWith(extra: updateReady),
        root: root.path,
        environment: const <String, String>{
          'DOVETAIL_UPDATE_KEY_PASSWORD': 'hunter2',
        },
      );

      expect(noteOn(report, 'update').finding, ProjectFinding.ready);
    });

    test('the internal channel with an update section should be missing, '
        'because ship refuses the same combination', () {
      // O ship recusa: um artefacto interno nao pode entrar no canal que quem
      // ja instalou le. O doctor dizia `ok update` para o mesmo yaml.
      final ProjectReport report = reportFor(
        config: configWith(extra: updateReady),
        channel: ShipChannel.internal,
      );

      expect(noteOn(report, 'update').finding, ProjectFinding.missing);
      expect(noteOn(report, 'update').detail, contains('internal'));
      expect(report.shipCanRelease, false);
    });

    test('notarize: true with nothing exported should be missing, naming the '
        'variables, because ship refuses the same yaml', () {
      final ProjectReport report = ProjectReport.of(
        config: configWith(extra: 'sign:\n  macos:\n    notarize: true\n'),
        version: '4.2.0',
        host: 'macos',
        environment: const <String, String>{},
      );

      expect(noteOn(report, 'signing').finding, ProjectFinding.missing);
      expect(
        noteOn(report, 'signing').detail,
        contains('APPLE_SIGNING_IDENTITY'),
      );
      expect(report.shipCanRelease, false);
    });

    test('notarize: true with identity but no notary credentials should name '
        'the credential groups', () {
      final ProjectReport report = ProjectReport.of(
        config: configWith(extra: 'sign:\n  macos:\n    notarize: true\n'),
        version: '4.2.0',
        host: 'macos',
        environment: const <String, String>{
          'APPLE_SIGNING_IDENTITY': 'Developer ID Application: Example',
        },
      );

      expect(noteOn(report, 'signing').finding, ProjectFinding.missing);
      expect(noteOn(report, 'signing').detail, contains('APPLE_ID'));
    });

    test('notarize: true with everything exported should be ready', () {
      final ProjectReport report = ProjectReport.of(
        config: configWith(extra: 'sign:\n  macos:\n    notarize: true\n'),
        version: '4.2.0',
        host: 'macos',
        environment: const <String, String>{
          'APPLE_SIGNING_IDENTITY': 'Developer ID Application: Example',
          'APPLE_ID': 'someone@example.com',
          'APPLE_PASSWORD': 'app-specific',
          'APPLE_TEAM_ID': 'TEAM123',
        },
      );

      expect(noteOn(report, 'signing').finding, ProjectFinding.ready);
      expect(noteOn(report, 'signing').detail, contains('notarised'));
    });

    test('notarize: false should stay ready with nothing exported: a local '
        'build ships unsigned and says so', () {
      final ProjectReport report = ProjectReport.of(
        config: configWith(extra: 'sign:\n  macos:\n    notarize: false\n'),
        version: '4.2.0',
        host: 'macos',
        environment: const <String, String>{},
      );

      expect(noteOn(report, 'signing').finding, ProjectFinding.ready);
    });

    test('no signing should say the build ships unsigned', () {
      expect(
        noteOn(reportFor(config: configWith()), 'signing').detail,
        contains('unsigned'),
      );
    });

    test('the signing note should follow the host', () {
      final DovetailConfig config = configWith(
        targets: 'darwin-aarch64, windows-x86_64',
        extra:
            'sign:\n  macos:\n    notarize: true\n'
            '  windows:\n    certificate-env: MY_CERT\n',
      );

      expect(
        noteOn(reportFor(config: config), 'signing').detail,
        contains('notarised'),
      );
      expect(
        noteOn(reportFor(config: config, host: 'windows'), 'signing').detail,
        'MY_CERT',
      );
    });

    const String windowsSigning =
        'sign:\n  windows:\n'
        '    certificate-env: MY_CERT\n'
        '    timestamp-url: http://timestamp.example.com\n';

    test('windows with no certificate exported should be missing on the '
        'release channel, naming the variable', () {
      // O installador sairia sem assinatura — o `sign` cai no caminho "sem
      // credencial, fica sem assinar" e devolve 0 —, e o doctor dizia
      // `ok signing MY_CERT` para um ambiente onde MY_CERT nem existia.
      final ProjectReport report = reportFor(
        config: configWith(extra: windowsSigning),
        host: 'windows',
        environment: const <String, String>{},
      );

      expect(noteOn(report, 'signing').finding, ProjectFinding.missing);
      expect(noteOn(report, 'signing').detail, contains('MY_CERT'));
      expect(noteOn(report, 'signing').detail, contains('unsigned'));
      expect(report.shipCanRelease, false);
    });

    test('windows with the certificate and the declared timestamp should be '
        'ready', () {
      final ProjectReport report = reportFor(
        config: configWith(extra: windowsSigning),
        host: 'windows',
        environment: const <String, String>{'MY_CERT': 'C:/cert.pfx'},
      );

      expect(noteOn(report, 'signing').finding, ProjectFinding.ready);
    });

    test('windows with a certificate but no timestamp server should be '
        'missing: the signature would die with the certificate', () {
      final ProjectReport report = reportFor(
        config: configWith(
          extra: 'sign:\n  windows:\n    certificate-env: MY_CERT\n',
        ),
        host: 'windows',
        environment: const <String, String>{'MY_CERT': 'C:/cert.pfx'},
      );

      expect(noteOn(report, 'signing').finding, ProjectFinding.missing);
      expect(noteOn(report, 'signing').detail, contains('timestamp'));
    });

    test('the internal channel should not demand a Windows certificate: it '
        'signs nothing for the store', () {
      final ProjectReport report = reportFor(
        config: configWith(extra: windowsSigning),
        host: 'windows',
        environment: const <String, String>{},
        channel: ShipChannel.internal,
      );

      expect(noteOn(report, 'signing').finding, ProjectFinding.ready);
    });

    test('linux needs no identity, and should not be told it lacks one', () {
      final ProjectNote note = noteOn(
        reportFor(
          config: configWith(targets: 'linux-x86_64'),
          host: 'linux',
        ),
        'signing',
      );

      expect(note.finding, ProjectFinding.ready);
      expect(note.detail, contains('checksums'));
    });

    test('a declared linux unit should be named by its file', () {
      final ProjectReport report = reportFor(
        config: configWith(
          extra:
              'service:\n  name: demo-helper.service\n'
              '  description: d\n  exec-start: /usr/lib/demo/helper\n',
        ),
      );

      expect(noteOn(report, 'service (linux)').detail, 'demo-helper.service');
    });

    test('a declared daemon whose binary was never built should be missing, '
        'naming the declared path', () {
      // O `build` recusa sem ele — o embed copia, nao compila — e o doctor
      // dizia `ok service (macos)` para o mesmo projeto. Dois comandos
      // discordando sobre o que pode empacotar, e um deles mentindo.
      final Directory root = Directory.systemTemp.createTempSync(
        'dovetail_daemon',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      final ProjectReport report = ProjectReport.of(
        config: configWith(extra: _macosDaemon),
        version: '4.2.0',
        host: 'macos',
        root: root.path,
      );

      expect(noteOn(report, 'service (macos)').finding, ProjectFinding.missing);
      expect(
        noteOn(report, 'service (macos)').detail,
        contains('target/release/demo-helper'),
      );
      expect(report.shipCanRelease, false);
    });

    test('a declared daemon whose binary is on disk should be ready', () {
      final Directory root = Directory.systemTemp.createTempSync(
        'dovetail_daemon',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      File(p.join(root.path, 'target', 'release', 'demo-helper'))
        ..createSync(recursive: true)
        ..writeAsStringSync('binary');

      final ProjectReport report = ProjectReport.of(
        config: configWith(extra: _macosDaemon),
        version: '4.2.0',
        host: 'macos',
        root: root.path,
      );

      expect(noteOn(report, 'service (macos)').finding, ProjectFinding.ready);
      expect(
        noteOn(report, 'service (macos)').detail,
        contains('com.example.demo.helper.plist'),
      );
    });

    test('a project with no macos daemon should keep saying none travels', () {
      final ProjectReport report = reportFor(
        config: configWith(
          extra:
              'service:\n  name: demo-helper.service\n'
              '  description: d\n  exec-start: /usr/lib/demo/helper\n',
        ),
      );

      expect(
        noteOn(report, 'service (macos)').finding,
        ProjectFinding.notConfigured,
      );
    });
  });

  group('the line each note prints', () {
    test('should mark ready, off and missing differently', () {
      expect(
        const ProjectNote(
          subject: 'update',
          finding: ProjectFinding.ready,
          detail: 'x',
        ).line,
        startsWith('ok'),
      );
      expect(
        const ProjectNote(
          subject: 'update',
          finding: ProjectFinding.notConfigured,
          detail: 'x',
        ).line,
        startsWith('off'),
      );
      expect(
        const ProjectNote(
          subject: 'update',
          finding: ProjectFinding.missing,
          detail: 'x',
        ).line,
        startsWith('missing'),
      );
    });
  });
}
