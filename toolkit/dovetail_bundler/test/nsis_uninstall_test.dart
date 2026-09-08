import 'dart:io';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

bool get _hasMakensis =>
    Process.runSync('which', <String>['makensis']).exitCode == 0;

BundleSpec specIn(String stage, String out) => BundleSpec(
  productName: 'Example Client',
  manufacturer: 'Example Ltda',
  identifier: 'io.example.client',
  version: AppVersion.parse('2.1.0'),
  mainBinaryName: 'client',
  appDirectory: stage,
  outputDirectory: out,
);

void main() {
  late Directory root;
  late String stage;
  late String out;

  setUp(() {
    root = Directory.systemTemp.createTempSync('nsis_un');
    stage = p.join(root.path, 'stage');
    out = p.join(root.path, 'out');
    Directory(stage).createSync(recursive: true);
    Directory(out).createSync(recursive: true);
    File(p.join(stage, 'client.exe')).writeAsStringSync('the runner');
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('the function the uninstaller calls', () {
    test('should exist under both names', () {
      expect(
        NsisUtils.source,
        contains('!insertmacro DovetailStrContainsBody ""'),
      );
      expect(
        NsisUtils.source,
        contains('!insertmacro DovetailStrContainsBody "un."'),
        reason:
            'NSIS refuses Call in an uninstall section unless the function is '
            'named un.something, so the body has to be instantiated twice',
      );
    });

    test('the running check should take the section it is in', () {
      expect(
        NsisUtils.source,
        contains('!macro CheckIfAppIsRunning UN executableName productName'),
      );
      expect(NsisUtils.source, contains(r'Call ${UN}DovetailStrContains'));
    });

    test('the install section should pass no prefix', () {
      expect(
        NsisScript.render(specIn(stage, out), TargetArch.x86_64),
        contains('CheckIfAppIsRunning "" '),
      );
    });

    test('the uninstall section should pass un.', () {
      final String script = NsisScript.render(
        specIn(stage, out),
        TargetArch.x86_64,
      );
      final int uninstall = script.indexOf('Section Uninstall');

      expect(uninstall, isNot(-1));
      expect(
        script.substring(uninstall),
        contains('CheckIfAppIsRunning "un." '),
        reason:
            'this is the call that made every generated script fail to '
            'compile, on Windows as much as anywhere else',
      );
    });
  });

  group('the unicode switch', () {
    test('should default to the unicode stub', () {
      expect(
        NsisScript.render(specIn(stage, out), TargetArch.x86_64),
        contains('Unicode true'),
      );
    });

    test('should be able to ask for the ansi one', () {
      expect(
        NsisScript.render(
          specIn(stage, out),
          TargetArch.x86_64,
          unicode: false,
        ),
        contains('Unicode false'),
      );
    });

    test('a bad_alloc should be reported as the stub, not as a mystery', () {
      expect(
        NsisBundler.crashedOnUnicodeStub(
          const ProcessOutcome(
            exitCode: -6,
            stdout: 'writing output (x86-unicode):',
            stderr: 'libc++abi: terminating due to std::bad_alloc',
          ),
        ),
        true,
      );
      expect(
        NsisBundler.unicodeStubRemedy,
        contains('system code page'),
        reason: 'the escape hatch has a cost and the message has to name it',
      );
    });

    test('an ordinary failure should keep its own message', () {
      expect(
        NsisBundler.crashedOnUnicodeStub(
          const ProcessOutcome(
            exitCode: 1,
            stdout: '',
            stderr: 'Error in script on line 12',
          ),
        ),
        false,
      );
    });
  });

  group('against the real makensis, on this machine', () {
    test(
      'the ansi stub should compile the generated script',
      () async {
        if (!_hasMakensis) {
          markTestSkipped('makensis is not installed');
          return;
        }

        final String produced = await NsisBundler(
          runner: const SystemProcessRunner(),
          makensis: 'makensis',
          pluginDirectory: p.join(root.path, 'plugins'),
          arch: TargetArch.x86_64,
          unicode: false,
        ).bundle(specIn(stage, out));

        final List<int> header = File(
          produced,
        ).readAsBytesSync().take(2).toList();
        expect(header, <int>[0x4D, 0x5A], reason: 'MZ, so it is a PE');
        expect(File(produced).lengthSync(), greaterThan(10000));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
