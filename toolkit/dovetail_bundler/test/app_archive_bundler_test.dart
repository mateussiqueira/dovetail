import 'dart:io';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final class _Recording implements ProcessRunner {
  final List<List<String>> calls = <List<String>>[];
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
    calls.add(<String>[executable, ...arguments]);
    this.environment = environment;
    // O tar de verdade nao roda; o arquivo que ele escreveria e escrito aqui
    // para a checagem de existencia passar.
    File(arguments[1]).writeAsStringSync('tar bytes');
    return const ProcessOutcome(exitCode: 0, stdout: '', stderr: '');
  }
}

BundleSpec _specFor(String appDirectory, String out) => BundleSpec(
  productName: 'Demo',
  manufacturer: 'M',
  identifier: 'com.example.demo',
  version: AppVersion.parse('4.2.0'),
  mainBinaryName: 'demo_app',
  appDirectory: appDirectory,
  outputDirectory: out,
);

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('app_archive'));
  tearDown(() => root.deleteSync(recursive: true));

  group('the name it writes', () {
    test(
      'should say .app.tar.gz, with the architecture suffix the dmg uses',
      () {
        final BundleSpec spec = _specFor('/x/demo_app.app', root.path);

        expect(
          const AppArchiveBundler(
            runner: SystemProcessRunner(),
          ).fileNameFor(spec),
          'demo_app_4.2.0.app.tar.gz',
        );
        expect(
          const AppArchiveBundler(
            runner: SystemProcessRunner(),
            requiredArchitectures: <TargetArch>{TargetArch.arm64},
          ).fileNameFor(spec),
          'demo_app_4.2.0_arm64.app.tar.gz',
        );
        expect(
          const AppArchiveBundler(
            runner: SystemProcessRunner(),
            requiredArchitectures: <TargetArch>{
              TargetArch.arm64,
              TargetArch.x86_64,
            },
          ).fileNameFor(spec),
          'demo_app_4.2.0_universal.app.tar.gz',
          reason:
              'o mesmo sufixo do dmg, para os dois artefatos casarem no dist/',
        );
      },
    );
  });

  group('what it hands tar', () {
    test('the bundle should sit at the root of the archive', () {
      final List<String> arguments =
          const AppArchiveBundler(runner: SystemProcessRunner()).argumentsFor(
            _specFor('/build/Release/demo_app.app', root.path),
            '/dist/demo_app_4.2.0.app.tar.gz',
          );

      expect(arguments, <String>[
        '-czf',
        '/dist/demo_app_4.2.0.app.tar.gz',
        '-C',
        '/build/Release',
        'demo_app.app',
      ]);
    });
  });

  group('what it hands tar, for real', () {
    test(
      'should run tar with COPYFILE_DISABLE and the bundle at the root',
      () async {
        // Um .app minimo que passa nas checagens de arquitetura e de versao
        // minima: sem exigencia de arquitetura, e com o Info.plist que o
        // MinimumSystemVersion le.
        final Directory app = Directory(p.join(root.path, 'demo_app.app'));
        Directory(p.join(app.path, 'Contents')).createSync(recursive: true);
        File(p.join(app.path, 'Contents', 'Info.plist')).writeAsStringSync(
          '<?xml version="1.0" encoding="UTF-8"?>\n'
          '<plist version="1.0"><dict>'
          '<key>LSMinimumSystemVersion</key><string>10.15</string>'
          '</dict></plist>\n',
        );
        final Directory out = Directory(p.join(root.path, 'dist'));
        final _Recording recording = _Recording();

        final String written = await AppArchiveBundler(
          runner: recording,
        ).bundle(_specFor(app.path, out.path));

        expect(written, p.join(out.path, 'demo_app_4.2.0.app.tar.gz'));
        expect(recording.calls.single, <String>[
          'tar',
          '-czf',
          written,
          '-C',
          root.path,
          'demo_app.app',
        ]);
        expect(
          recording.environment,
          <String, String>{'COPYFILE_DISABLE': '1'},
          reason:
              'o tar do macOS grava entradas ._* por padrao, que o tar de '
              'extracao recria como arquivos soltos dentro do bundle assinado',
        );
      },
    );
  });

  group('what it refuses', () {
    test('a missing app should be refused, naming the build', () async {
      await expectLater(
        const AppArchiveBundler(
          runner: SystemProcessRunner(),
        ).bundle(_specFor(p.join(root.path, 'nope.app'), root.path)),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.remedy,
            'remedy',
            contains('flutter build macos'),
          ),
        ),
      );
    });

    test('a directory that is not an .app should be refused', () async {
      final Directory notApp = Directory(p.join(root.path, 'Release'))
        ..createSync();

      await expectLater(
        const AppArchiveBundler(
          runner: SystemProcessRunner(),
        ).bundle(_specFor(notApp.path, root.path)),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.message,
            'message',
            contains('not an .app bundle'),
          ),
        ),
      );
    });
  });
}
