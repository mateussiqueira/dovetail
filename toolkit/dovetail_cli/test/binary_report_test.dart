import 'package:dovetail_cli/src/doctor/binary_report.dart';
import 'package:dovetail_cli/src/doctor/project_report.dart';
import 'package:test/test.dart';

void main() {
  const String tree =
      'dovetail 0.1.0 (unknown-unknown, dart unknown, commit source)';
  const String binary =
      'dovetail 0.1.0 (macos-arm64, dart 3.12.2, commit e95c894)';
  const Set<String> nineteen = <String>{
    'init',
    'doctor',
    'dev',
    'bridge',
    'build',
    'bundle',
    'sign',
    'icon',
    'keygen',
    'inspect',
    'manifest',
    'new',
    'probe',
    'release',
    'self-install',
    'self-update',
    'ship',
    'update',
    'upgrade',
  };

  group('reading the other binary', () {
    test('the commit is the token after "commit" in --version', () {
      expect(BinaryReport.commitOf(binary), 'e95c894');
      expect(BinaryReport.commitOf(tree), 'source');
    });

    test('a --version without a commit should read as none, not crash', () {
      expect(
        BinaryReport.commitOf('dovetail 0.1.0 (macos-arm64, dart 3.12.2)'),
        isNull,
        reason: 'um binário anterior ao campo não carrega o commit',
      );
    });

    test('commands are the first column under "Available commands:"', () {
      const String help =
          'The dovetail desktop toolkit.\n'
          '\n'
          'Usage: dovetail <command> [arguments]\n'
          '\n'
          'Global options:\n'
          '-h, --help    Print this usage information.\n'
          '\n'
          'Available commands:\n'
          '  build    Builds the Flutter desktop app this host can build.\n'
          '  doctor   Reports which platform tools are present and actually usable.\n'
          '  help     Display help information for dovetail.\n'
          '\n'
          'Run "dovetail help <command>" for more information about a command.\n';

      expect(BinaryReport.commandsOf(help), <String>{
        'build',
        'doctor',
        'help',
      });
    });

    test('a help text with no command section should read as empty', () {
      expect(BinaryReport.commandsOf('usage: something else\n'), isEmpty);
    });
  });

  group('finding it on PATH', () {
    test('the first directory that has it wins, in PATH order', () {
      final String? found = BinaryReport.findOnPath(
        '/usr/local/bin:/Users/me/.local/bin:/opt/dovetail/bin',
        separator: ':',
        names: const <String>['dovetail'],
        exists: (String path) =>
            path == '/Users/me/.local/bin/dovetail' ||
            path == '/opt/dovetail/bin/dovetail',
      );

      expect(found, '/Users/me/.local/bin/dovetail');
    });

    test('no PATH, an empty PATH, and a PATH without it all read as none', () {
      bool never(String _) => false;
      expect(
        BinaryReport.findOnPath(null, exists: never, separator: ':'),
        isNull,
      );
      expect(
        BinaryReport.findOnPath('', exists: never, separator: ':'),
        isNull,
      );
      expect(
        BinaryReport.findOnPath(
          '/a::/b',
          exists: never,
          separator: ':',
          names: const <String>['dovetail'],
        ),
        isNull,
        reason: 'um segmento vazio no PATH não vira "./dovetail"',
      );
    });
  });

  group('the verdict', () {
    ProjectNote only(BinaryReport report) {
      expect(report.notes, hasLength(1));
      return report.notes.single;
    }

    test('no dovetail on PATH should be off and name both ways to get one', () {
      final ProjectNote note = only(
        BinaryReport.of(
          onPath: null,
          isThisProcess: false,
          onPathVersion: null,
          onPathCommands: null,
          thisVersion: tree,
          thisCommands: nineteen,
        ),
      );

      expect(note.finding, ProjectFinding.notConfigured);
      expect(note.detail, contains('build_release.sh --install'));
      expect(note.detail, contains('self-install'));
    });

    test('the binary being this very process should be ok, and say so', () {
      final ProjectNote note = only(
        BinaryReport.of(
          onPath: '/Users/me/.local/bin/dovetail',
          isThisProcess: true,
          onPathVersion: binary,
          onPathCommands: nineteen,
          thisVersion: binary,
          thisCommands: nineteen,
        ),
      );

      expect(note.finding, ProjectFinding.ready);
      expect(note.detail, contains('this one'));
      expect(note.detail, contains('e95c894'));
    });

    test('a binary that knows fewer commands should be off and NAME them', () {
      final ProjectNote note = only(
        BinaryReport.of(
          onPath: '/Users/me/.local/bin/dovetail',
          isThisProcess: false,
          onPathVersion: binary,
          onPathCommands: nineteen.difference(<String>{'probe', 'new'}),
          thisVersion: tree,
          thisCommands: nineteen,
        ),
      );

      expect(note.finding, ProjectFinding.notConfigured);
      expect(note.detail, contains('2 fewer commands'));
      expect(
        note.detail,
        contains('new, probe'),
        reason:
            'quem lê precisa saber QUAL comando vai faltar, não só que falta',
      );
      expect(note.detail, contains('build_release.sh --install'));
    });

    test('one missing command should not say "commands"', () {
      final ProjectNote note = only(
        BinaryReport.of(
          onPath: '/x/dovetail',
          isThisProcess: false,
          onPathVersion: binary,
          onPathCommands: nineteen.difference(<String>{'probe'}),
          thisVersion: tree,
          thisCommands: nineteen,
        ),
      );

      expect(note.detail, contains('1 fewer command than'));
    });

    test('a binary that knows MORE commands is newer than the checkout', () {
      final ProjectNote note = only(
        BinaryReport.of(
          onPath: '/x/dovetail',
          isThisProcess: false,
          onPathVersion: binary,
          onPathCommands: nineteen.union(<String>{'publish'}),
          thisVersion: tree,
          thisCommands: nineteen,
        ),
      );

      expect(note.finding, ProjectFinding.ready);
      expect(note.detail, contains('publish'));
      expect(note.detail, contains('newer than this checkout'));
    });

    test('same commands and same commit should be plainly ok', () {
      final ProjectNote note = only(
        BinaryReport.of(
          onPath: '/x/dovetail',
          isThisProcess: false,
          onPathVersion: binary,
          onPathCommands: nineteen,
          thisVersion: binary,
          thisCommands: nineteen,
        ),
      );

      expect(note.finding, ProjectFinding.ready);
      expect(note.detail, contains('same commit, e95c894'));
    });

    test(
      'same commands from a different commit should stay ok but name both',
      () {
        final ProjectNote note = only(
          BinaryReport.of(
            onPath: '/x/dovetail',
            isThisProcess: false,
            onPathVersion: binary,
            onPathCommands: nineteen,
            thisVersion: tree,
            thisCommands: nineteen,
          ),
        );

        expect(
          note.finding,
          ProjectFinding.ready,
          reason:
              'nada falta ainda; o aviso forte é reservado a comando ausente',
        );
        expect(note.detail, contains('e95c894'));
        expect(note.detail, contains('this checkout'));
        expect(note.detail, contains('build_release.sh --install'));
      },
    );

    test(
      'something on PATH that does not answer should be off, not a crash',
      () {
        final ProjectNote note = only(
          BinaryReport.of(
            onPath: '/x/dovetail',
            isThisProcess: false,
            onPathVersion: null,
            onPathCommands: null,
            thisVersion: tree,
            thisCommands: nineteen,
          ),
        );

        expect(note.finding, ProjectFinding.notConfigured);
        expect(note.detail, contains('did not answer'));
      },
    );
  });
}
