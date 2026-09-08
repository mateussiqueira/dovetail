import 'package:dovetail_signer/dovetail_signer.dart';
import 'package:test/test.dart';

final class CountingRunner implements ProcessRunner {
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
    return const ProcessOutcome(exitCode: 0, stdout: '', stderr: '');
  }
}

const AuthenticodeRequest _request = AuthenticodeRequest(
  thumbprint: 'ABCDEF0123',
  timestampUrl: 'http://timestamp.example.com',
);

void main() {
  group('what argumentsFor refuses', () {
    const Authenticode sut = Authenticode(runner: _NoopRunner());

    test('an empty thumbprint should be a refusal, not an assert', () {
      expect(
        () => sut.argumentsFor(
          const AuthenticodeRequest(
            thumbprint: '   ',
            timestampUrl: 'http://timestamp.example.com',
          ),
          'setup.exe',
        ),
        throwsA(
          isA<SigningFailure>().having(
            (SigningFailure failure) => failure.remedy,
            'remedy',
            contains('not compiled into a release build'),
          ),
        ),
        reason:
            'an assert guarded this, and dart compile exe strips it, so a '
            'release build handed signtool /sha1 with nothing after it',
      );
    });

    test('an empty digest algorithm should be refused', () {
      expect(
        () => sut.argumentsFor(
          const AuthenticodeRequest(
            thumbprint: 'ABCDEF',
            timestampUrl: 'http://timestamp.example.com',
            digestAlgorithm: '',
          ),
          'setup.exe',
        ),
        throwsA(isA<SigningFailure>()),
      );
    });

    test('a complete request should still produce the command', () {
      expect(
        sut.argumentsFor(
          const AuthenticodeRequest(
            thumbprint: 'ABCDEF',
            timestampUrl: 'http://timestamp.example.com',
          ),
          'setup.exe',
        ),
        containsAllInOrder(<String>[
          'sign',
          '/fd',
          'sha256',
          '/sha1',
          'ABCDEF',
        ]),
      );
    });
  });

  test('signtool should get the digest, the thumbprint and the timestamp', () {
    const Authenticode sut = Authenticode(runner: _NoopRunner());

    expect(sut.argumentsFor(_request, r'C:\out\example.exe'), <String>[
      'sign',
      '/fd',
      'sha256',
      '/sha1',
      'ABCDEF0123',
      '/tr',
      'http://timestamp.example.com',
      '/td',
      'sha256',
      r'C:\out\example.exe',
    ]);
  });

  test('an empty timestamp url should be fatal, with no default supplied', () {
    const Authenticode sut = Authenticode(runner: _NoopRunner());
    const AuthenticodeRequest request = AuthenticodeRequest(
      thumbprint: 'ABCDEF0123',
      timestampUrl: '   ',
    );

    expect(
      () => sut.argumentsFor(request, 'example.exe'),
      throwsA(
        isA<SigningFailure>().having(
          (SigningFailure failure) => failure.remedy,
          'remedy',
          contains('becomes invalid the day the certificate expires'),
        ),
      ),
      reason:
          'Tauri signs without a timestamp when none is configured, and there '
          'is no fallback in its code either',
    );
  });

  test(
    'signing an empty list should be fatal instead of a silent success',
    () async {
      final Authenticode sut = Authenticode(runner: CountingRunner());

      await expectLater(
        sut.signAll(request: _request, files: const <String>[]),
        throwsA(
          isA<SigningFailure>().having(
            (SigningFailure failure) => failure.remedy,
            'remedy',
            contains('unsigned helper reaches a customer'),
          ),
        ),
      );
    },
  );

  test('every file handed over should be signed', () async {
    final CountingRunner runner = CountingRunner();
    final Authenticode sut = Authenticode(runner: runner);

    await sut.signAll(
      request: _request,
      files: const <String>['app.exe', 'helper.exe', 'core.dll'],
    );

    expect(runner.calls.length, 3);
    expect(runner.calls.map((List<String> c) => c.last), <String>[
      'app.exe',
      'helper.exe',
      'core.dll',
    ]);
  });

  test(
    'the credential group should demand a timestamp url alongside the cert',
    () {
      expect(
        AuthenticodeCredentials.thumbprint
            .missingIn(const <String, String>{
              'WINDOWS_CERTIFICATE_THUMBPRINT': 'ABC',
            })
            .single
            .name,
        'WINDOWS_TIMESTAMP_URL',
      );
    },
  );
}

final class _NoopRunner implements ProcessRunner {
  const _NoopRunner();

  @override
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdin,
    Duration? timeout,
  }) async => const ProcessOutcome(exitCode: 0, stdout: '', stderr: '');
}
