import 'package:dovetail_signer/dovetail_signer.dart';
import 'package:test/test.dart';

final class ScriptedRunner implements ProcessRunner {
  ScriptedRunner({this.failOn});

  final String? failOn;
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
    final bool fails = failOn != null && arguments.join(' ').contains(failOn!);
    return ProcessOutcome(
      exitCode: fails ? 1 : 0,
      stdout: '',
      stderr: fails ? 'refused' : '',
    );
  }
}

const String _bundle = '/tmp/Example.app';

const List<String> _contents = <String>[
  '/tmp/Example.app/Contents/MacOS/Example',
  '/tmp/Example.app/Contents/Frameworks/FlutterMacOS.framework',
  '/tmp/Example.app/Contents/Frameworks/libcore.dylib',
  '/tmp/Example.app/Contents/Library/LaunchDaemons/io.example.helper.plist',
  '/tmp/Example.app/Contents/Helpers/io.example.helper',
  '/tmp/Example.app/Contents/Resources/icon.icns',
];

void main() {
  test('the bundle itself should be signed last', () {
    final List<SignTarget> order = SignOrder.insideOut(
      bundlePath: _bundle,
      contents: _contents,
    );

    expect(order.last.path, _bundle);
    expect(order.last.isExecutable, true);
  });

  test('nested code should be signed before the bundle, deepest first', () {
    final List<SignTarget> order = SignOrder.insideOut(
      bundlePath: _bundle,
      contents: _contents,
    );

    final int deepest = order.indexWhere(
      (SignTarget t) => t.path.endsWith('MacOS/Example'),
    );
    final int bundle = order.indexWhere((SignTarget t) => t.path == _bundle);

    expect(deepest, lessThan(bundle));
  });

  test('a resource outside the nested code folders should not be signed', () {
    final List<SignTarget> order = SignOrder.insideOut(
      bundlePath: _bundle,
      contents: _contents,
    );

    expect(order.any((SignTarget t) => t.path.endsWith('icon.icns')), false);
  });

  test('a dylib should not be treated as an executable', () {
    final List<SignTarget> order = SignOrder.insideOut(
      bundlePath: _bundle,
      contents: _contents,
    );
    final SignTarget dylib = order.firstWhere(
      (SignTarget t) => t.path.endsWith('.dylib'),
    );

    expect(dylib.isExecutable, false);
  });

  test('every codesign call should carry an explicit timestamp', () {
    const MacosSigner sut = MacosSigner(runner: _NoopRunner());
    const MacosSigningRequest request = MacosSigningRequest(
      bundlePath: _bundle,
      identity: 'Developer ID Application: Example',
    );

    for (final SignTarget target in SignOrder.insideOut(
      bundlePath: _bundle,
      contents: _contents,
    )) {
      expect(
        sut.argumentsFor(request, target),
        contains('--timestamp'),
        reason:
            'Tauri omits it, and codesign then timestamps some signatures and '
            'not others',
      );
    }
  });

  test('hardened runtime should reach executables and skip libraries', () {
    const MacosSigner sut = MacosSigner(runner: _NoopRunner());
    const MacosSigningRequest request = MacosSigningRequest(
      bundlePath: _bundle,
      identity: 'Example',
    );
    final List<SignTarget> order = SignOrder.insideOut(
      bundlePath: _bundle,
      contents: _contents,
    );

    final SignTarget executable = order.firstWhere(
      (SignTarget t) => t.path.endsWith('MacOS/Example'),
    );
    final SignTarget dylib = order.firstWhere(
      (SignTarget t) => t.path.endsWith('.dylib'),
    );

    expect(
      sut.argumentsFor(request, executable),
      containsAll(<String>['--options', 'runtime']),
    );
    expect(sut.argumentsFor(request, dylib), isNot(contains('runtime')));
  });

  test('entitlements should reach the app but never a framework', () {
    const MacosSigner sut = MacosSigner(runner: _NoopRunner());
    const MacosSigningRequest request = MacosSigningRequest(
      bundlePath: _bundle,
      identity: 'Example',
      appEntitlements: '/tmp/app.entitlements',
    );
    final List<SignTarget> order = SignOrder.insideOut(
      bundlePath: _bundle,
      contents: _contents,
    );

    final SignTarget bundle = order.last;
    final SignTarget dylib = order.firstWhere(
      (SignTarget t) => t.path.endsWith('.dylib'),
    );

    expect(
      sut.argumentsFor(request, bundle),
      containsAll(<String>['--entitlements', '/tmp/app.entitlements']),
    );
    expect(sut.argumentsFor(request, dylib), isNot(contains('--entitlements')));
  });

  test('a daemon should get its own entitlements, not the app ones', () {
    const MacosSigner sut = MacosSigner(runner: _NoopRunner());
    const MacosSigningRequest request = MacosSigningRequest(
      bundlePath: _bundle,
      identity: 'Example',
      appEntitlements: '/tmp/app.entitlements',
      entitlementsByRelativePath: <String, String>{
        'Contents/Helpers/io.example.helper': '/tmp/daemon.entitlements',
      },
    );
    final List<SignTarget> order = SignOrder.insideOut(
      bundlePath: _bundle,
      contents: _contents,
    );
    final SignTarget helper = order.firstWhere(
      (SignTarget t) => t.path.endsWith('io.example.helper'),
    );

    expect(
      sut.argumentsFor(request, helper),
      containsAll(<String>['--entitlements', '/tmp/daemon.entitlements']),
      reason:
          'Tauri applies one entitlements file to every nested item, so a '
          'privileged daemon would inherit the app entitlements',
    );
  });

  test(
    'sign should clear extended attributes before the first codesign',
    () async {
      final ScriptedRunner runner = ScriptedRunner();
      final MacosSigner sut = MacosSigner(runner: runner);

      await sut.sign(
        request: const MacosSigningRequest(
          bundlePath: _bundle,
          identity: 'Example',
        ),
        contents: _contents,
      );

      expect(runner.calls.first.first, 'xattr');
      expect(runner.calls.first, contains('-crs'));
      expect(runner.calls[1].first, 'codesign');
    },
  );

  test('a codesign failure should stop the run and name the file', () async {
    final ScriptedRunner runner = ScriptedRunner(failOn: 'libcore.dylib');
    final MacosSigner sut = MacosSigner(runner: runner);

    await expectLater(
      sut.sign(
        request: const MacosSigningRequest(
          bundlePath: _bundle,
          identity: 'Example',
        ),
        contents: _contents,
      ),
      throwsA(
        isA<SigningFailure>().having(
          (SigningFailure failure) => failure.message,
          'message',
          contains('libcore.dylib'),
        ),
      ),
    );

    final Iterable<List<String>> signed = runner.calls.where(
      (List<String> call) => call.first == 'codesign',
    );

    expect(
      signed.any((List<String> call) => call.last == _bundle),
      false,
      reason: 'the bundle must not be signed after a nested item failed',
    );
  });

  test('notarisation should archive with ditto, not zip', () {
    const Notarizer sut = Notarizer(runner: _NoopRunner());

    expect(
      sut.archiveArguments(
        bundlePath: _bundle,
        archivePath: '/tmp/Example.zip',
      ),
      <String>[
        '-c',
        '-k',
        '--keepParent',
        '--sequesterRsrc',
        _bundle,
        '/tmp/Example.zip',
      ],
    );
  });

  test('the Apple ID group should demand the team id', () {
    expect(
      NotarizationCredentials.appleId
          .missingIn(const <String, String>{
            'APPLE_ID': 'a',
            'APPLE_PASSWORD': 'b',
          })
          .single
          .name,
      'APPLE_TEAM_ID',
    );
  });

  group('a flat file, which is what the dmg is', () {
    test('should carry the identity and the timestamp, and nothing meant '
        'for code', () {
      final List<String> arguments = const MacosSigner(
        runner: _NoopRunner(),
      ).fileArguments(path: '/tmp/Example.dmg', identity: 'Developer ID X');

      expect(arguments, <String>[
        '--force',
        '--timestamp',
        '--sign',
        'Developer ID X',
        '/tmp/Example.dmg',
      ]);
      expect(
        arguments,
        isNot(contains('--options')),
        reason: 'o hardened runtime e de codigo executavel, nao de uma imagem',
      );
      expect(arguments, isNot(contains('--entitlements')));
    });

    test('signFile should call codesign once and never xattr', () async {
      final ScriptedRunner runner = ScriptedRunner();

      await MacosSigner(
        runner: runner,
      ).signFile(path: '/tmp/Example.dmg', identity: 'Developer ID X');

      expect(runner.calls, hasLength(1));
      expect(runner.calls.single.first, 'codesign');
      expect(runner.calls.single.last, '/tmp/Example.dmg');
    });

    test('a refused codesign should surface with what codesign said', () async {
      final ScriptedRunner runner = ScriptedRunner(failOn: 'Example.dmg');

      await expectLater(
        MacosSigner(
          runner: runner,
        ).signFile(path: '/tmp/Example.dmg', identity: 'Developer ID X'),
        throwsA(
          isA<SigningFailure>().having(
            (SigningFailure failure) => failure.remedy,
            'remedy',
            'refused',
          ),
        ),
      );
    });
  });
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
