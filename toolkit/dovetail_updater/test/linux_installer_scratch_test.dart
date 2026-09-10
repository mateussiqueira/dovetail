import 'dart:io';
import 'dart:typed_data';

import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:test/test.dart';

/// A runner that never gets to answer: the process could not even start.
final class _Throwing implements ProcessRunner {
  @override
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdin,
    Duration? timeout,
  }) async => throw const ProcessException('pkexec', <String>[], 'not found');
}

VerifiedArtifact _artifact(String name) => VerifiedArtifact.trusted(
  bytes: Uint8List.fromList('the new build'.codeUnits),
  sourceUrl: 'https://cdn.example/$name',
  trustedComment: 'built by the release command',
);

void main() {
  test(
    'a runner that throws should leave no scratch directory behind',
    () async {
      // Red before the try/finally: the delete sat after the await, so a runner
      // that threw skipped it and the package stayed in the system temp
      // directory. Twenty-odd of those per test run is how 81 came to be found
      // on the host that runs the tests.
      final Directory scratch = Directory.systemTemp.createTempSync(
        'dovetail_test',
      );
      addTearDown(() {
        if (scratch.existsSync()) scratch.deleteSync(recursive: true);
      });

      await expectLater(
        LinuxInstaller(
          runner: _Throwing(),
          // Required by the constructor, unused by the .deb branch: the package
          // manager path never looks at where the AppImage lives.
          appImagePath: '${scratch.path}/App-x86_64.AppImage',
          scratchDirectory: scratch.path,
        ).install(_artifact('client_2.1.0_amd64.deb')),
        throwsA(isA<ProcessException>()),
      );

      expect(scratch.existsSync(), false);
    },
  );
}
