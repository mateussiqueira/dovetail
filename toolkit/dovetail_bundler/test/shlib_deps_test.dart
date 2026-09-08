import 'dart:io';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final class _FakeRunner implements ProcessRunner {
  _FakeRunner({
    this.stdout = '',
    this.stderr = '',
    this.exitCode = 0,
    this.throwing = false,
  });

  final String stdout;
  final String stderr;
  final int exitCode;
  final bool throwing;
  final List<List<String>> calls = <List<String>>[];
  String? workingDirectory;

  @override
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    String? stdin,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    if (throwing) {
      throw ProcessException(executable, arguments, 'No such file', 2);
    }
    calls.add(<String>[executable, ...arguments]);
    this.workingDirectory = workingDirectory;
    return ProcessOutcome(exitCode: exitCode, stdout: stdout, stderr: stderr);
  }
}

void main() {
  late Directory root;
  late String app;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_shlibs_test');
    app = p.join(root.path, 'bundle');
    Directory(p.join(app, 'lib')).createSync(recursive: true);
    File(p.join(app, 'client')).writeAsStringSync('elf');
    File(p.join(app, 'lib', 'libapp.so')).writeAsStringSync('so');
    File(p.join(app, 'lib', 'libflutter.so')).writeAsStringSync('so');
    File(p.join(app, 'data', 'icudtl.dat'))
      ..createSync(recursive: true)
      ..writeAsStringSync('data');
  });

  tearDown(() => root.deleteSync(recursive: true));

  BundleSpec specOf() => BundleSpec(
    productName: 'Example',
    manufacturer: 'Example Ltda',
    identifier: 'io.example.client',
    version: AppVersion.parse('1.0.0'),
    mainBinaryName: 'client',
    appDirectory: app,
    outputDirectory: p.join(root.path, 'out'),
  );

  group('the dependencies it derives', () {
    test('the engine libraries should be named where a scanner cannot', () {
      expect(FlutterRuntimeLibraries.debian, <String>['libegl1', 'libgles2']);
      expect(FlutterRuntimeLibraries.rpm, <String>[
        'libglvnd-egl',
        'libglvnd-gles',
      ]);
      expect(FlutterRuntimeLibraries.because, contains('dlopen'));
    });

    test('should read the field dpkg prints, versions and all', () {
      expect(
        ShlibDeps.parse(
          'shlibs:Depends=libc6 (>= 2.34), libgtk-3-0 (>= 3.21.4), zlib1g\n',
        ),
        <String>['libc6 (>= 2.34)', 'libgtk-3-0 (>= 3.21.4)', 'zlib1g'],
      );
    });

    test('should ignore the warnings dpkg prints before the field', () {
      expect(
        ShlibDeps.parse(
          'dpkg-shlibdeps: warning: package could avoid a useless dependency\n'
          'shlibs:Depends=libc6 (>= 2.34)\n',
        ),
        <String>['libc6 (>= 2.34)'],
      );
    });

    test('should answer nothing when the field is absent', () {
      expect(ShlibDeps.parse('dpkg-shlibdeps: error: something\n'), isEmpty);
    });

    test('should hand dpkg the binary and every shared object', () async {
      final _FakeRunner runner = _FakeRunner(stdout: 'shlibs:Depends=libc6\n');

      await ShlibDeps(runner: runner).forBundle(specOf());

      final List<String> call = runner.calls.single;
      expect(call.first, 'dpkg-shlibdeps');
      expect(call, contains(p.join(app, 'client')));
      expect(call, contains(p.join(app, 'lib', 'libapp.so')));
      expect(call, contains(p.join(app, 'lib', 'libflutter.so')));
      expect(
        call.where((String entry) => entry.endsWith('icudtl.dat')),
        isEmpty,
        reason: 'dpkg-shlibdeps refuses a file that is not an ELF object',
      );
    });

    test('should run outside the bundle it reads', () async {
      final _FakeRunner runner = _FakeRunner(stdout: 'shlibs:Depends=libc6\n');

      await ShlibDeps(runner: runner).forBundle(specOf());

      expect(
        runner.workingDirectory,
        isNot(app),
        reason:
            'dpkg-shlibdeps needs a debian/control beside it, and writing one '
            'into the bundle would ship it inside the package',
      );
    });

    test('a host without the tool should derive nothing, not fail', () async {
      expect(
        await ShlibDeps(
          runner: _FakeRunner(throwing: true),
        ).forBundle(specOf()),
        isEmpty,
        reason:
            'dpkg-shlibdeps exists on Debian and nowhere else, and a macOS '
            'build of a deb is a thing this toolkit does on purpose',
      );
    });

    test('should hand dpkg absolute paths, since it runs elsewhere', () async {
      final _FakeRunner runner = _FakeRunner(stdout: 'shlibs:Depends=libc6\n');

      // baseDirectory, never `Directory.current = root`. cwd belongs to the
      // PROCESS and `dart test` runs every suite as an isolate of one
      // process, so parking it here made other suites resolve their repo root
      // against a temp directory — universal_binary_test.dart and
      // mach_o_test.dart lose theirs that way, and their guards then report
      // it as 'the artefact was not built'. Reproducible: this trio under
      // `-j 8` skipped three tests in silence on the 7th run.
      final BundleSpec relative = BundleSpec(
        productName: 'Example',
        manufacturer: 'Example Ltda',
        identifier: 'io.example.client',
        version: AppVersion.parse('1.0.0'),
        mainBinaryName: 'client',
        appDirectory: 'bundle',
        outputDirectory: 'out',
      );

      await ShlibDeps(
        runner: runner,
        baseDirectory: root.path,
      ).forBundle(relative);

      for (final String argument in runner.calls.single.skip(3)) {
        expect(
          p.isAbsolute(argument),
          true,
          reason:
              'the tool runs in a scratch directory that holds the '
              'debian/control it needs, so a path relative to the project '
              'resolves against the wrong place and it finds nothing: '
              '$argument',
        );
      }
    });

    test(
      'a tool that runs and fails should be a refusal, not silence',
      () async {
        await expectLater(
          ShlibDeps(
            runner: _FakeRunner(
              exitCode: 2,
              stdout: '',
              stderr: 'no such file',
            ),
          ).forBundle(specOf()),
          throwsA(
            isA<BundleFailure>().having(
              (BundleFailure failure) => failure.remedy,
              'remedy',
              contains('installs and then fails to start'),
            ),
          ),
        );
      },
    );

    test('an app directory that is not there should derive nothing', () async {
      final _FakeRunner runner = _FakeRunner();
      final BundleSpec missing = BundleSpec(
        productName: 'Example',
        manufacturer: 'Example Ltda',
        identifier: 'io.example.client',
        version: AppVersion.parse('1.0.0'),
        mainBinaryName: 'client',
        appDirectory: p.join(root.path, 'nowhere'),
        outputDirectory: p.join(root.path, 'out'),
      );

      expect(await ShlibDeps(runner: runner).forBundle(missing), isEmpty);
      expect(runner.calls, isEmpty);
    });
  });
}
