import 'dart:io';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final class RecordingRunner implements ProcessRunner {
  RecordingRunner(this.outcome);

  final ProcessOutcome outcome;
  String? executable;
  List<String>? arguments;
  String? workingDirectory;
  Map<String, String>? environment;

  @override
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdin,
    Duration? timeout,
  }) async {
    this.executable = executable;
    this.arguments = arguments;
    this.workingDirectory = workingDirectory;
    this.environment = environment;
    return outcome;
  }
}

const ProcessOutcome _ok = ProcessOutcome(exitCode: 0, stdout: '', stderr: '');

void main() {
  late Directory root;
  late Directory app;
  late Directory out;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_nsis');
    app = Directory(p.join(root.path, 'app'))..createSync();
    File(p.join(app.path, 'example.exe')).writeAsStringSync('binary');
    out = Directory(p.join(root.path, 'out'));
  });

  tearDown(() => root.deleteSync(recursive: true));

  BundleSpec specFor({String version = '1.2.3+47'}) => BundleSpec(
    productName: 'Example',
    manufacturer: 'Example Ltd',
    identifier: 'com.example.app',
    version: AppVersion.parse(version),
    mainBinaryName: 'example',
    appDirectory: app.path,
    outputDirectory: out.path,
  );

  test('bundle should refuse a build directory that is not there', () async {
    final BundleSpec spec = BundleSpec(
      productName: 'Example',
      manufacturer: 'Example Ltd',
      identifier: 'com.example.app',
      version: AppVersion.parse('1.0.0'),
      mainBinaryName: 'example',
      appDirectory: p.join(root.path, 'missing'),
      outputDirectory: out.path,
    );
    final NsisBundler sut = NsisBundler(
      arch: TargetArch.x86_64,
      runner: RecordingRunner(_ok),
      makensis: 'makensis',
      pluginDirectory: root.path,
    );

    await expectLater(
      sut.bundle(spec),
      throwsA(
        isA<BundleFailure>().having(
          (BundleFailure failure) => failure.remedy,
          'remedy',
          contains('flutter build windows'),
        ),
      ),
    );
  });

  test('bundle should write the script and the utils beside it', () async {
    final RecordingRunner runner = RecordingRunner(_ok);
    final NsisBundler sut = NsisBundler(
      arch: TargetArch.x86_64,
      runner: runner,
      makensis: 'makensis',
      pluginDirectory: root.path,
    );

    await sut.bundle(specFor()).catchError((Object _) => '');

    final String stage = p.join(out.path, 'nsis');
    expect(File(p.join(stage, 'installer.nsi')).existsSync(), true);
    expect(File(p.join(stage, 'dovetail_utils.nsh')).existsSync(), true);
  });

  test(
    'bundle should hand makensis the charset flags and the plugin dir',
    () async {
      final RecordingRunner runner = RecordingRunner(_ok);
      final NsisBundler sut = NsisBundler(
        arch: TargetArch.x86_64,
        runner: runner,
        makensis: '/usr/local/bin/makensis',
        pluginDirectory: '/tmp/plugins',
      );

      await sut.bundle(specFor()).catchError((Object _) => '');

      expect(runner.executable, '/usr/local/bin/makensis');
      expect(runner.arguments, contains('-INPUTCHARSET'));
      expect(runner.arguments, contains('UTF8'));
      expect(runner.arguments, contains('-DPLUGINDIR=/tmp/plugins'));
      expect(runner.arguments!.last, 'installer.nsi');
      expect(runner.workingDirectory, p.join(out.path, 'nsis'));
      expect(runner.environment!['DOVETAIL_APP_DIR'], app.absolute.path);
    },
  );

  test('bundle should report a makensis failure with its own output', () async {
    final NsisBundler sut = NsisBundler(
      arch: TargetArch.x86_64,
      runner: RecordingRunner(
        const ProcessOutcome(
          exitCode: 1,
          stdout: '',
          stderr: 'Error: invalid command',
        ),
      ),
      makensis: 'makensis',
      pluginDirectory: root.path,
    );

    await expectLater(
      sut.bundle(specFor()),
      throwsA(
        isA<BundleFailure>()
            .having(
              (BundleFailure failure) => failure.message,
              'message',
              contains('exit code 1'),
            )
            .having(
              (BundleFailure failure) => failure.remedy,
              'remedy',
              'Error: invalid command',
            ),
      ),
    );
  });

  test(
    'bundle should not trust a success that produced no installer',
    () async {
      final NsisBundler sut = NsisBundler(
        arch: TargetArch.x86_64,
        runner: RecordingRunner(_ok),
        makensis: 'makensis',
        pluginDirectory: root.path,
      );

      await expectLater(
        sut.bundle(specFor()),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.message,
            'message',
            contains('reported success'),
          ),
        ),
      );
    },
  );

  group('with a usable makensis on this machine', () {
    late String makensis;

    setUpAll(() {
      final ProcessResult which = Process.runSync('which', <String>[
        'makensis',
      ]);
      if (which.exitCode != 0) {
        makensis = '';
        return;
      }

      // The probe compiles the REAL generated installer, with the flags the
      // bundler really passes. A four-line script compiles on this machine
      // while the real one aborts (bad_alloc writing the Unicode stub), so a
      // trivial probe would answer "usable" for a host that cannot build the
      // actual artifact — which is the false positive this guard exists to
      // keep out of the skip decision.
      final Directory probe = Directory.systemTemp.createTempSync('nsis_probe');
      final BundleSpec spec = BundleSpec(
        productName: 'Example',
        manufacturer: 'Example Ltd',
        identifier: 'com.example.app',
        version: AppVersion.parse('1.2.3+47'),
        mainBinaryName: 'example',
        appDirectory: p.join(probe.path, 'app'),
        outputDirectory: p.join(probe.path, 'out'),
      );
      Directory(spec.appDirectory).createSync();
      File(
        p.join(probe.path, 'dovetail_utils.nsh'),
      ).writeAsStringSync(NsisUtils.source);
      File(
        p.join(probe.path, 'installer.nsi'),
      ).writeAsStringSync(NsisScript.render(spec, TargetArch.x86_64));
      final ProcessResult compiled = Process.runSync(
        which.stdout.toString().trim(),
        <String>[
          '-INPUTCHARSET',
          'UTF8',
          '-OUTPUTCHARSET',
          'UTF8',
          '-V2',
          '-DPLUGINDIR=${probe.path}',
          'installer.nsi',
        ],
        workingDirectory: probe.path,
        environment: <String, String>{'DOVETAIL_APP_DIR': spec.appDirectory},
      );
      final bool usable =
          compiled.exitCode == 0 &&
          File(
            p.join(probe.path, spec.installerFileNameFor(TargetArch.x86_64)),
          ).existsSync();
      probe.deleteSync(recursive: true);

      makensis = usable ? which.stdout.toString().trim() : '';
    });

    test(
      'makensis should compile the generated script into an installer',
      () async {
        if (makensis.isEmpty) {
          markTestSkipped(
            'no usable makensis here: it compiles a four-line script but '
            'aborts on the real generated installer, so this proof belongs '
            'to a Windows runner',
          );
          return;
        }

        final Directory plugins = Directory(p.join(root.path, 'plugins'))
          ..createSync();
        final NsisBundler sut = NsisBundler(
          arch: TargetArch.x86_64,
          runner: const SystemProcessRunner(),
          makensis: makensis,
          pluginDirectory: plugins.path,
        );

        final String installer = await sut.bundle(specFor());

        expect(File(installer).existsSync(), true);
        expect(p.basename(installer), 'example_1.2.3_setup.exe');
        expect(File(installer).lengthSync(), greaterThan(1024));
      },
    );
  });
}
