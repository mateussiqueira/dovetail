import 'package:dovetail_process_runner/dovetail_process_runner.dart';
import 'package:test/test.dart';

const ProcessRunner _runner = SystemProcessRunner();

void main() {
  group('a child that will not finish', () {
    test('should be killed at the limit, not waited on', () async {
      final Stopwatch clock = Stopwatch()..start();

      await expectLater(
        _runner.run('sleep', <String>[
          '30',
        ], timeout: const Duration(milliseconds: 400)),
        throwsA(isA<ProcessTimeout>()),
      );
      clock.stop();

      expect(
        clock.elapsed,
        lessThan(const Duration(seconds: 5)),
        reason:
            'a notarytool that hangs used to hold the whole release with no '
            'output saying why',
      );
    });

    test('the failure should name the tool and the limit', () async {
      try {
        await _runner.run('sleep', <String>[
          '30',
        ], timeout: const Duration(milliseconds: 300));
        fail('it should not have finished');
      } on ProcessTimeout catch (timeout) {
        expect(timeout.executable, 'sleep');
        expect(timeout.limit, const Duration(milliseconds: 300));
        expect(timeout.toString(), contains('was killed'));
      }
    });

    test('what it printed before the kill should survive', () async {
      try {
        await _runner.run('sh', <String>[
          '-c',
          'echo submitting; sleep 30',
        ], timeout: const Duration(milliseconds: 400));
        fail('it should not have finished');
      } on ProcessTimeout catch (timeout) {
        expect(
          timeout.stdout,
          contains('submitting'),
          reason:
              'the last thing a hanging tool said is the only clue to where '
              'it stopped',
        );
      }
    });
  });

  group('a child that finishes', () {
    test('should not be affected by a limit it beats', () async {
      final ProcessOutcome outcome = await _runner.run('echo', <String>[
        'quick',
      ], timeout: const Duration(seconds: 10));

      expect(outcome.succeeded, true);
      expect(outcome.stdout.trim(), 'quick');
    });

    test('should still work with no limit at all', () async {
      final ProcessOutcome outcome = await _runner.run('echo', <String>['x']);

      expect(outcome.succeeded, true);
      expect(outcome.stdout.trim(), 'x');
    });

    test('stdin should still reach it under a limit', () async {
      final ProcessOutcome outcome = await _runner.run(
        'cat',
        <String>[],
        stdin: 'through the pipe',
        timeout: const Duration(seconds: 10),
      );

      expect(outcome.stdout, 'through the pipe');
    });

    test('a large stdin should not deadlock', () async {
      final String payload = 'x' * (1024 * 256);
      final ProcessOutcome outcome = await _runner.run(
        'cat',
        <String>[],
        stdin: payload,
        timeout: const Duration(seconds: 20),
      );

      expect(
        outcome.stdout.length,
        payload.length,
        reason:
            'writing stdin before draining stdout fills the pipe buffer and '
            'both sides wait forever',
      );
    });
  });
}
