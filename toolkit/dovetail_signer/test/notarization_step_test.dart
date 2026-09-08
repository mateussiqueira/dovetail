import 'package:dovetail_signer/dovetail_signer.dart';
import 'package:test/test.dart';

final class _Recording implements ProcessRunner {
  final List<List<String>> calls = <List<String>>[];
  final List<String?> workingDirectories = <String?>[];

  @override
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdin,
    Duration? timeout,
  }) async {
    calls.add(<String>[executable, ...arguments]);
    workingDirectories.add(workingDirectory);
    final bool submitting = arguments.contains('submit');
    return ProcessOutcome(
      exitCode: 0,
      stdout: submitting ? '{"status":"Accepted","id":"abc"}' : '',
      stderr: '',
    );
  }
}

final class _Rejecting implements ProcessRunner {
  final List<List<String>> calls = <List<String>>[];

  @override
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdin,
    Duration? timeout,
  }) async {
    calls.add(<String>[executable, ...arguments]);
    return ProcessOutcome(
      exitCode: 0,
      stdout: arguments.contains('submit')
          ? '{"status":"Invalid","id":"abc"}'
          : '',
      stderr: '',
    );
  }
}

const Map<String, String> _appleId = <String, String>{
  'APPLE_ID': 'someone@example.com',
  'APPLE_PASSWORD': 'app-specific',
  'APPLE_TEAM_ID': 'TEAM123',
};

const Map<String, String> _apiKey = <String, String>{
  'APPLE_API_KEY_ID': 'KEY123',
  'APPLE_API_ISSUER': 'ISSUER123',
  'APPLE_API_KEY_PATH': '/keys/AuthKey.p8',
};

void main() {
  group('NotarytoolArguments.forWhicheverIsConfigured', () {
    test('should pick the Apple ID set when it is complete', () {
      expect(
        NotarytoolArguments.forWhicheverIsConfigured(_appleId),
        containsAllInOrder(<String>['--apple-id', 'someone@example.com']),
      );
    });

    test('should pick the API key set when it is complete', () {
      expect(
        NotarytoolArguments.forWhicheverIsConfigured(_apiKey),
        containsAllInOrder(<String>['--key-id', 'KEY123']),
      );
    });

    test('should prefer the Apple ID set when both are complete', () {
      expect(
        NotarytoolArguments.forWhicheverIsConfigured(<String, String>{
          ..._appleId,
          ..._apiKey,
        }),
        contains('--apple-id'),
      );
    });

    test('no credentials at all should be null, not a crash', () {
      expect(
        NotarytoolArguments.forWhicheverIsConfigured(const <String, String>{}),
        isNull,
        reason:
            'reading the API key set before deciding it was configured used to '
            'raise a null check operator error and exit 255',
      );
    });

    test('a half-configured set should name what is missing', () {
      expect(
        () => NotarytoolArguments.forWhicheverIsConfigured(
          const <String, String>{'APPLE_API_KEY_ID': 'KEY123'},
        ),
        throwsA(
          isA<SigningFailure>()
              .having(
                (SigningFailure failure) => failure.message,
                'message',
                allOf(
                  contains('APPLE_API_ISSUER'),
                  contains('APPLE_API_KEY_PATH'),
                ),
              )
              .having(
                (SigningFailure failure) => failure.remedy,
                'remedy',
                contains('already been paid for'),
              ),
        ),
      );
    });

    test('a half-configured Apple ID set should also refuse', () {
      expect(
        () => NotarytoolArguments.forWhicheverIsConfigured(
          const <String, String>{'APPLE_ID': 'someone@example.com'},
        ),
        throwsA(isA<SigningFailure>()),
      );
    });

    test('an empty value should count as unset, not as a credential', () {
      expect(
        NotarytoolArguments.forWhicheverIsConfigured(const <String, String>{
          'APPLE_ID': '',
          'APPLE_PASSWORD': '',
          'APPLE_TEAM_ID': '',
        }),
        isNull,
      );
    });

    test('a missing variable should be named, not asserted away', () {
      expect(
        () => NotarytoolArguments.forApiKey(const <String, String>{
          'APPLE_API_KEY_ID': 'KEY123',
        }),
        throwsA(
          isA<SigningFailure>().having(
            (SigningFailure failure) => failure.message,
            'message',
            contains('APPLE_API_KEY_PATH'),
          ),
        ),
      );
    });
  });

  group('NotarizationStep', () {
    test('should submit and staple when credentials are complete', () async {
      final _Recording runner = _Recording();
      final NotarizationOutcome outcome = await NotarizationStep(
        runner: runner,
      ).run(bundlePath: '/out/Example.app', environment: _appleId);

      expect(outcome, NotarizationOutcome.notarised);
      final String flat = runner.calls
          .map((List<String> call) => call.join(' '))
          .join('\n');
      expect(flat, contains('notarytool'));
      expect(flat, contains('submit'));
      expect(flat, contains('--wait'));
      expect(flat, contains('stapler'));
    });

    test('should do nothing when no credentials are set', () async {
      final _Recording runner = _Recording();
      final NotarizationOutcome outcome = await NotarizationStep(runner: runner)
          .run(
            bundlePath: '/out/Example.app',
            environment: const <String, String>{},
          );

      expect(outcome, NotarizationOutcome.noCredentials);
      expect(runner.calls, isEmpty);
    });

    test(
      'should refuse a half-configured set before running anything',
      () async {
        final _Recording runner = _Recording();
        await expectLater(
          NotarizationStep(runner: runner).run(
            bundlePath: '/out/Example.app',
            environment: const <String, String>{'APPLE_ID': 'a@b.c'},
          ),
          throwsA(isA<SigningFailure>()),
        );
        expect(runner.calls, isEmpty);
      },
    );

    test('the archive it submits should sit beside the bundle', () async {
      final _Recording runner = _Recording();
      await NotarizationStep(
        runner: runner,
      ).run(bundlePath: '/out/Example.app', environment: _apiKey);

      expect(
        runner.calls.map((List<String> call) => call.join(' ')).join('\n'),
        contains('/out/Example.app.zip'),
      );
    });
  });

  group('NotarizationStep on a flat file', () {
    test(
      'should submit the file itself, with no ditto, and staple it',
      () async {
        final _Recording runner = _Recording();

        final NotarizationOutcome outcome = await NotarizationStep(
          runner: runner,
        ).runOnFile(path: '/tmp/out/Example.dmg', environment: _appleId);

        expect(outcome, NotarizationOutcome.notarised);
        expect(
          runner.calls.where((List<String> call) => call.first == 'ditto'),
          isEmpty,
          reason: 'o notary service aceita a imagem como esta; o zip e do .app',
        );
        final List<String> submit = runner.calls.firstWhere(
          (List<String> call) => call.contains('submit'),
        );
        expect(submit, contains('/tmp/out/Example.dmg'));
        final List<String> staple = runner.calls.firstWhere(
          (List<String> call) => call.contains('staple'),
        );
        expect(
          staple.last,
          'Example.dmg',
          reason: 'o ticket e grampeado na imagem, que e o que o usuario baixa',
        );
        expect(
          runner.workingDirectories[runner.calls.indexOf(staple)],
          '/tmp/out',
          reason: 'stapler recebe o nome; a pasta e o cwd, e sem ela nao acha',
        );
      },
    );

    test('a status other than Accepted should refuse, not staple', () async {
      final _Rejecting runner = _Rejecting();

      await expectLater(
        NotarizationStep(
          runner: runner,
        ).runOnFile(path: '/tmp/out/Example.dmg', environment: _appleId),
        throwsA(
          isA<SigningFailure>().having(
            (SigningFailure failure) => failure.message,
            'message',
            contains('Invalid'),
          ),
        ),
      );
      expect(
        runner.calls.where((List<String> call) => call.contains('staple')),
        isEmpty,
      );
    });

    test('no credentials should say so and touch nothing', () async {
      final _Recording runner = _Recording();

      final NotarizationOutcome outcome = await NotarizationStep(runner: runner)
          .runOnFile(
            path: '/tmp/out/Example.dmg',
            environment: const <String, String>{},
          );

      expect(outcome, NotarizationOutcome.noCredentials);
      expect(runner.calls, isEmpty);
    });
  });
}
