import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:test/test.dart';

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
}) => ProjectReport.of(config: config, version: version, host: host);

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

    test('a declared service should be named by its unit file', () {
      final ProjectReport report = reportFor(
        config: configWith(
          extra:
              'service:\n  name: demo-helper.service\n'
              '  description: d\n  exec-start: /usr/lib/demo/helper\n',
        ),
      );

      expect(noteOn(report, 'service').detail, 'demo-helper.service');
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
