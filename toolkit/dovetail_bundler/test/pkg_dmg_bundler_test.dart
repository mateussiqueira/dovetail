import 'dart:io';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final class _Recording implements ProcessRunner {
  final List<List<String>> calls = <List<String>>[];
  final Map<String, String> staged = <String, String>{};
  String? volume;
  String? source;

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
    if (executable == 'pkgbuild' || executable == 'productbuild') {
      File(arguments.last).writeAsStringSync('pkg bytes');
    }
    if (executable == 'hdiutil') {
      volume = arguments[arguments.indexOf('-volname') + 1];
      source = arguments[arguments.indexOf('-srcfolder') + 1];
      for (final FileSystemEntity entity in Directory(source!).listSync()) {
        if (entity is File) {
          staged[p.basename(entity.path)] = entity.readAsStringSync();
        }
      }
      File(arguments.last).writeAsStringSync('dmg bytes');
    }
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

LaunchDaemon _daemon() =>
    LaunchDaemon(label: 'com.example.demo.helper', program: 'demo-helper');

MacosServiceScripts _scriptsFor(LaunchDaemon daemon) => MacosServiceScripts(
  daemon: daemon,
  identifier: 'com.example.demo',
  applicationPath: '/Applications/Demo.app',
);

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('dovetail_pkgdmg'));
  tearDown(() => root.deleteSync(recursive: true));

  String appWithHelper() {
    final String app = p.join(root.path, 'Demo.app');
    File(p.join(app, 'Contents', 'Info.plist'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '<plist version="1.0"><dict>'
        '<key>LSMinimumSystemVersion</key><string>11.0</string>'
        '</dict></plist>',
      );
    File(p.join(app, 'Contents', 'MacOS', 'demo-helper'))
      ..createSync(recursive: true)
      ..writeAsStringSync('mach-o bytes');
    return app;
  }

  String instructionsWith(String body) {
    final String path = p.join(root.path, 'LEIA-ME.txt');
    File(path).writeAsStringSync(body);
    return path;
  }

  group('the pkg inside the dmg', () {
    test('names the file with the pkg stem', () {
      final BundleSpec spec = _specFor('/x/Demo.app', root.path);
      expect(
        const PkgDmgBundler(runner: SystemProcessRunner()).fileNameFor(spec),
        'demo_app_4.2.0.dmg',
      );
    });

    test('mounts the image from the pkg folder, not the app', () async {
      final _Recording recording = _Recording();
      final String app = appWithHelper();
      final LaunchDaemon daemon = _daemon();
      final String text = instructionsWith('Rode @PKG@ para instalar.\n');

      final String produced = await PkgDmgBundler(
        runner: recording,
        instructions: text,
        daemon: daemon,
        scripts: _scriptsFor(daemon),
      ).bundle(_specFor(app, root.path));

      expect(produced, p.join(root.path, 'demo_app_4.2.0.dmg'));
      expect(recording.volume, 'Demo');
      expect(recording.source, isNot(app));
      expect(
        recording.staged.keys,
        containsAll(<String>['demo_app_4.2.0.pkg', 'LEIA-ME.txt']),
      );
      expect(
        recording.staged['LEIA-ME.txt'],
        'Rode demo_app_4.2.0.pkg para instalar.\n',
      );
      final List<String> hdiutil = recording.calls.firstWhere(
        (List<String> call) => call.first == 'hdiutil',
      );
      expect(hdiutil, containsAllInOrder(<String>['-format', 'UDZO']));
    });

    test('refuses with no instructions', () {
      final LaunchDaemon daemon = _daemon();
      expect(
        () => PkgDmgBundler(
          runner: _Recording(),
          daemon: daemon,
          scripts: _scriptsFor(daemon),
        ).bundle(_specFor(appWithHelper(), root.path)),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('refuses an instructions path that is not there', () {
      final LaunchDaemon daemon = _daemon();
      expect(
        () => PkgDmgBundler(
          runner: _Recording(),
          instructions: p.join(root.path, 'missing.txt'),
          daemon: daemon,
          scripts: _scriptsFor(daemon),
        ).bundle(_specFor(appWithHelper(), root.path)),
        throwsA(isA<BundleFailure>()),
      );
    });
  });

  group('the image a real hdiutil produces', () {
    test('carries the pkg and the text, proven by mounting it', () async {
      if (!Platform.isMacOS) {
        markTestSkipped('needs macOS');
        return;
      }
      final String app = appWithHelper();
      final LaunchDaemon daemon = _daemon();
      final String text = instructionsWith('Instale @PKG@.\n');

      final String dmg = await PkgDmgBundler(
        runner: const SystemProcessRunner(),
        instructions: text,
        daemon: daemon,
        scripts: _scriptsFor(daemon),
      ).bundle(_specFor(app, root.path));

      final Directory mount = Directory(p.join(root.path, 'mnt'))..createSync();
      final ProcessResult attached = Process.runSync('hdiutil', <String>[
        'attach',
        dmg,
        '-nobrowse',
        '-readonly',
        '-mountpoint',
        mount.path,
      ]);
      expect(attached.exitCode, 0, reason: attached.stderr.toString());
      try {
        final List<String> inside =
            mount
                .listSync()
                .map((FileSystemEntity e) => p.basename(e.path))
                .toList()
              ..sort();
        print('dmg contem: $inside');
        print(
          'LEIA-ME: '
          '${File(p.join(mount.path, 'LEIA-ME.txt')).readAsStringSync().trim()}',
        );
        expect(
          inside,
          containsAll(<String>['demo_app_4.2.0.pkg', 'LEIA-ME.txt']),
        );
        expect(
          File(p.join(mount.path, 'LEIA-ME.txt')).readAsStringSync(),
          contains('demo_app_4.2.0.pkg'),
        );
      } finally {
        Process.runSync('hdiutil', <String>['detach', mount.path, '-quiet']);
      }
    });
  });
}
