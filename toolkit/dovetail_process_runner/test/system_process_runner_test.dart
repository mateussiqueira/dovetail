import 'dart:io';

import 'package:dovetail_process_runner/dovetail_process_runner.dart';
import 'package:test/test.dart';

void main() {
  const SystemProcessRunner sut = SystemProcessRunner();

  group('a listener on the way through', () {
    test('should hear each chunk as it arrives, not at the exit', () async {
      final List<String> heard = <String>[];
      final List<DateTime> when = <DateTime>[];
      final SystemProcessRunner tee = SystemProcessRunner(
        onStdout: (String chunk) {
          heard.add(chunk);
          when.add(DateTime.now());
        },
      );

      final ProcessOutcome outcome = await tee.run('sh', <String>[
        '-c',
        'echo first; sleep 0.6; echo second',
      ]);
      final DateTime done = DateTime.now();

      expect(heard.join(), outcome.stdout, reason: 'repassado E guardado');
      expect(heard.first, contains('first'));
      expect(
        done.difference(when.first),
        greaterThan(const Duration(milliseconds: 300)),
        reason:
            'o primeiro pedaco foi ouvido enquanto o filho ainda dormia — e '
            'isso que separa "ao vivo" de "no fim"',
      );
    });

    test('stderr should have its own listener, and stay separate', () async {
      final List<String> out = <String>[];
      final List<String> err = <String>[];
      final SystemProcessRunner tee = SystemProcessRunner(
        onStdout: out.add,
        onStderr: err.add,
      );

      final ProcessOutcome outcome = await tee.run('sh', <String>[
        '-c',
        'echo out; echo err >&2',
      ]);

      expect(out.join().trim(), 'out');
      expect(err.join().trim(), 'err');
      expect(outcome.stderr.trim(), 'err');
    });
  });

  group('without stdin', () {
    test('should carry the exit code and the output back', () async {
      final ProcessOutcome outcome = await sut.run('sh', <String>[
        '-c',
        'echo out; echo err >&2; exit 0',
      ]);
      expect(outcome.succeeded, true);
      expect(outcome.stdout.trim(), 'out');
      expect(outcome.stderr.trim(), 'err');
    });

    test('a non-zero exit should not be reported as success', () async {
      final ProcessOutcome outcome = await sut.run('sh', <String>[
        '-c',
        'exit 3',
      ]);
      expect(outcome.exitCode, 3);
      expect(outcome.succeeded, false);
    });

    test('should honour the working directory', () async {
      final Directory scratch = Directory.systemTemp.createTempSync('pr_cwd');
      addTearDown(() => scratch.deleteSync(recursive: true));

      final ProcessOutcome outcome = await sut.run('sh', <String>[
        '-c',
        'pwd',
      ], workingDirectory: scratch.path);
      expect(
        outcome.stdout.trim(),
        endsWith(
          scratch.uri.pathSegments.where((String s) => s.isNotEmpty).last,
        ),
      );
    });

    test('should pass the environment it was given', () async {
      final ProcessOutcome outcome = await sut.run(
        'sh',
        <String>['-c', r'printf %s "$DOVETAIL_PROBE"'],
        environment: const <String, String>{'DOVETAIL_PROBE': 'carried'},
      );
      expect(outcome.stdout, 'carried');
    });

    test(
      'an executable that does not exist should surface, not hang',
      () async {
        await expectLater(
          sut.run('a-binary-nobody-installed', const <String>[]),
          throwsA(isA<ProcessException>()),
        );
      },
    );
  });

  group('with stdin', () {
    test('should deliver what it was given on stdin', () async {
      final ProcessOutcome outcome = await sut.run('sh', <String>[
        '-c',
        'read line; printf %s "got:\$line"',
      ], stdin: 'a-secret\n');
      expect(outcome.stdout, 'got:a-secret');
    });

    test('should still separate stdout from stderr', () async {
      final ProcessOutcome outcome = await sut.run('sh', <String>[
        '-c',
        'read x; echo o; echo e >&2',
      ], stdin: 'x\n');
      expect(outcome.stdout.trim(), 'o');
      expect(outcome.stderr.trim(), 'e');
    });

    test(
      'a large stdin against a child filling stdout should not deadlock',
      () async {
        final ProcessOutcome outcome = await sut
            .run('sh', <String>[
              '-c',
              r'i=0; while [ $i -lt 4000 ]; do '
                  r'printf "%s\n" "0123456789012345678901234567890123456789"; '
                  r'i=$((i+1)); done; cat >/dev/null; exit 0',
            ], stdin: '${'x' * 65536}\n')
            .timeout(
              const Duration(seconds: 20),
              onTimeout: () => throw StateError(
                'deadlocked: the child filled stdout while nothing drained it, '
                'and stdin.flush never returned',
              ),
            );

        expect(outcome.succeeded, true, reason: outcome.stderr);
        expect(outcome.stdout.length, greaterThan(160000));
      },
    );

    test('a large output before stdin is read should not deadlock', () async {
      final ProcessOutcome outcome = await sut
          .run('sh', <String>[
            '-c',
            r'i=0; while [ $i -lt 4000 ]; do '
                r'printf "%s\n" "0123456789012345678901234567890123456789"; '
                r'i=$((i+1)); done; read line; printf %s "then:$line"',
          ], stdin: 'late\n')
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw StateError(
              'deadlocked: the child filled the stdout pipe while nothing '
              'drained it, and stdin.flush never returned',
            ),
          );

      expect(outcome.succeeded, true, reason: outcome.stderr);
      expect(outcome.stdout, endsWith('then:late'));
      expect(outcome.stdout.length, greaterThan(160000));
    });

    test('a large output on stderr should not deadlock either', () async {
      final ProcessOutcome outcome = await sut
          .run('sh', <String>[
            '-c',
            r'i=0; while [ $i -lt 4000 ]; do '
                r'printf "%s\n" "0123456789012345678901234567890123456789" >&2; '
                r'i=$((i+1)); done; read line; exit 0',
          ], stdin: 'late\n')
          .timeout(const Duration(seconds: 20));

      expect(outcome.succeeded, true);
      expect(outcome.stderr.length, greaterThan(160000));
    });

    test('a non-zero exit with stdin should still report the code', () async {
      final ProcessOutcome outcome = await sut.run('sh', <String>[
        '-c',
        'read x; exit 7',
      ], stdin: 'x\n');
      expect(outcome.exitCode, 7);
    });
  });

  group('ProcessOutcome.firstDiagnostic', () {
    test('should prefer stderr when it has anything', () {
      expect(
        const ProcessOutcome(
          exitCode: 1,
          stdout: 'noise\n',
          stderr: '  error WIX0144: bad\nmore\n',
        ).firstDiagnostic,
        'error WIX0144: bad',
      );
    });

    test('should fall back to stdout when stderr is blank', () {
      expect(
        const ProcessOutcome(
          exitCode: 1,
          stdout: '\n\n  the real reason\n',
          stderr: '   \n',
        ).firstDiagnostic,
        'the real reason',
      );
    });

    test('should name the exit code when there is no output at all', () {
      expect(
        const ProcessOutcome(
          exitCode: 11,
          stdout: '',
          stderr: '',
        ).firstDiagnostic,
        'exit code 11',
      );
    });
  });
}
