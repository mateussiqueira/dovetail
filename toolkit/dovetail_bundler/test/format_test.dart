import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

late Directory root;
late Directory out;

BundleSpec specFor(String appDirectory) => BundleSpec(
  productName: 'Example',
  manufacturer: 'Example Ltd',
  identifier: 'com.example.app',
  version: AppVersion.parse('1.2.3+47'),
  mainBinaryName: 'example',
  appDirectory: appDirectory,
  outputDirectory: out.path,
  homepage: 'https://example.com',
);

void main() {
  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_formats');
    out = Directory(p.join(root.path, 'dist'));
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('the deb', () {
    late Directory app;

    setUp(() {
      app = Directory(p.join(root.path, 'bundle'))..createSync();
      File(p.join(app.path, 'example')).writeAsStringSync('#!/bin/sh\ntrue\n');
      Directory(
        p.join(app.path, 'data', 'flutter_assets'),
      ).createSync(recursive: true);
      File(
        p.join(app.path, 'data', 'flutter_assets', 'AssetManifest.json'),
      ).writeAsStringSync('{}');
    });

    test(
      'control should name the package, the version and the architecture',
      () {
        const DebBundler sut = DebBundler(depends: <String>['libgtk-3-0']);

        final String control = sut.controlFor(
          specFor(app.path),
          installedKiB: 42,
        );

        expect(control, contains('Package: example'));
        expect(control, contains('Version: 1.2.3'));
        expect(control, contains('Architecture: amd64'));
        expect(control, contains('Installed-Size: 42'));
        expect(control, contains('Depends: libgtk-3-0'));
        expect(control, contains('Homepage: https://example.com'));
      },
    );

    test('control should leave Depends out when nothing is declared', () {
      const DebBundler sut = DebBundler();

      expect(
        sut.controlFor(specFor(app.path), installedKiB: 1),
        isNot(contains('Depends:')),
      );
    });

    test('bundle should refuse a build directory that is not there', () async {
      const DebBundler sut = DebBundler();

      await expectLater(
        sut.bundle(specFor(p.join(root.path, 'missing'))),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('bundle should refuse an empty build directory', () async {
      final Directory empty = Directory(p.join(root.path, 'empty'))
        ..createSync();
      const DebBundler sut = DebBundler();

      await expectLater(
        sut.bundle(specFor(empty.path)),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.message,
            'message',
            contains('no files to package'),
          ),
        ),
      );
    });

    test('the system ar should read the three members in order', () async {
      const DebBundler sut = DebBundler();
      final String deb = await sut.bundle(specFor(app.path));

      final ProcessResult listed = Process.runSync('ar', <String>['t', deb]);

      expect(listed.exitCode, 0, reason: listed.stderr.toString());
      expect(listed.stdout.toString().trim().split('\n'), <String>[
        'debian-binary',
        'control.tar.gz',
        'data.tar.gz',
      ]);
    });

    test('debian-binary should hold exactly the format version', () async {
      const DebBundler sut = DebBundler();
      final String deb = await sut.bundle(specFor(app.path));
      final Directory extract = Directory(p.join(root.path, 'x'))..createSync();

      Process.runSync('ar', <String>['x', deb], workingDirectory: extract.path);

      expect(
        File(p.join(extract.path, 'debian-binary')).readAsStringSync(),
        '2.0\n',
      );
    });

    test(
      'the system tar should read data.tar.gz and find the payload',
      () async {
        const DebBundler sut = DebBundler();
        final String deb = await sut.bundle(specFor(app.path));
        final Directory extract = Directory(p.join(root.path, 'x'))
          ..createSync();
        Process.runSync('ar', <String>[
          'x',
          deb,
        ], workingDirectory: extract.path);

        final ProcessResult listed = Process.runSync('tar', <String>[
          'tzf',
          'data.tar.gz',
        ], workingDirectory: extract.path);

        expect(listed.exitCode, 0, reason: listed.stderr.toString());
        final String names = listed.stdout.toString();
        expect(names, contains('usr/lib/example/example'));
        expect(
          names,
          contains('usr/lib/example/data/flutter_assets/AssetManifest.json'),
        );
        expect(
          names,
          contains('usr/share/applications/com.example.app.desktop'),
          reason:
              'a Wayland compositor matches the app id against the installed '
              'file name, so a short name is a name no portal ever finds',
        );
      },
    );

    test('the control member should carry the control file', () async {
      const DebBundler sut = DebBundler();
      final String deb = await sut.bundle(specFor(app.path));
      final Directory extract = Directory(p.join(root.path, 'x'))..createSync();
      Process.runSync('ar', <String>['x', deb], workingDirectory: extract.path);

      final ProcessResult read = Process.runSync('tar', <String>[
        'xzfO',
        'control.tar.gz',
        'control',
      ], workingDirectory: extract.path);

      expect(read.exitCode, 0, reason: read.stderr.toString());
      expect(read.stdout.toString(), contains('Package: example'));
    });

    test('an odd sized member should be padded so the next header aligns', () {
      final List<int> archive = DebBundler.writeAr(<ArMember>[
        ArMember('odd', Uint8List.fromList(utf8.encode('abc'))),
        ArMember('next', Uint8List.fromList(utf8.encode('xy'))),
      ]);

      expect(archive.length.isEven, true);
      expect(String.fromCharCodes(archive).contains('next'), true);
    });
  });

  group('the dmg', () {
    test('hdiutil should get the volume name and the source folder', () {
      const DmgBundler sut = DmgBundler(runner: _NoopRunner());
      final BundleSpec spec = specFor('/tmp/Example.app');

      final List<String> arguments = sut.argumentsFor(spec, '/tmp/out.dmg');

      expect(arguments, containsAllInOrder(<String>['-volname', 'Example']));
      expect(
        arguments,
        containsAllInOrder(<String>['-srcfolder', '/tmp/Example.app']),
      );
      expect(arguments, containsAllInOrder(<String>['-format', 'UDZO']));
    });

    test(
      'bundle should refuse a directory that is not an app bundle',
      () async {
        final Directory plain = Directory(p.join(root.path, 'plain'))
          ..createSync();
        const DmgBundler sut = DmgBundler(runner: _NoopRunner());

        await expectLater(
          sut.bundle(specFor(plain.path)),
          throwsA(
            isA<BundleFailure>().having(
              (BundleFailure failure) => failure.remedy,
              'remedy',
              contains('the .app itself'),
            ),
          ),
        );
      },
    );

    test('hdiutil should produce a dmg the system can attach', () async {
      if (!Platform.isMacOS) {
        markTestSkipped('needs macOS');
        return;
      }

      final Directory app = Directory(p.join(root.path, 'Example.app'))
        ..createSync();
      Directory(
        p.join(app.path, 'Contents', 'MacOS'),
      ).createSync(recursive: true);
      File(
        p.join(app.path, 'Contents', 'MacOS', 'Example'),
      ).writeAsStringSync('binary');
      // A bundle with no Info.plist is not a bundle, and the dmg bundler now
      // says so. The fixture had none because nothing used to read it.
      File(p.join(app.path, 'Contents', 'Info.plist')).writeAsStringSync(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<plist version="1.0"><dict>\n'
        '<key>LSMinimumSystemVersion</key><string>10.15</string>\n'
        '</dict></plist>\n',
      );

      const DmgBundler sut = DmgBundler(runner: SystemProcessRunner());
      final String dmg = await sut.bundle(specFor(app.path));

      expect(File(dmg).existsSync(), true);
      expect(p.basename(dmg), 'example_1.2.3.dmg');

      final ProcessResult verified = Process.runSync('hdiutil', <String>[
        'verify',
        dmg,
      ]);
      expect(verified.exitCode, 0, reason: verified.stderr.toString());
    });
  });
  group('AppVersion build metadata', () {
    test('should accept plain digits', () {
      expect(AppVersion.parse('1.2.3+4').windowsFileVersion, '1.2.3.4');
      expect(AppVersion.parse('1.2.3+0').windowsFileVersion, '1.2.3.0');
    });

    test('should refuse a signed build, which parses as an integer', () {
      expect(
        () => AppVersion.parse('1.2.3+-5'),
        throwsA(isA<BundleFailure>()),
        reason:
            'int.tryParse accepted it and produced the file version 1.2.3.-5, '
            'which no installer reads back',
      );
    });

    test('should refuse a hex build, which parses as an integer too', () {
      expect(
        () => AppVersion.parse('1.2.3+0x10'),
        throwsA(isA<BundleFailure>()),
        reason: 'int.tryParse turned +0x10 into build 16, silently',
      );
    });

    test('should refuse a build with a space or a sign', () {
      for (final String raw in <String>['1.2.3+ 4', '1.2.3++4', '1.2.3+4.5']) {
        expect(
          () => AppVersion.parse(raw),
          throwsA(isA<BundleFailure>()),
          reason: raw,
        );
      }
    });
  });

  group('the rpm', () {
    late Directory app;

    setUp(() {
      app = Directory(p.join(root.path, 'bundle'))..createSync();
      File(p.join(app.path, 'example')).writeAsStringSync('#!/bin/sh\ntrue\n');
    });

    test('the spec should name the package and pin the architecture', () {
      const RpmBundler sut = RpmBundler(
        runner: _NoopRunner(),
        requires: <String>['gtk3'],
      );

      final String spec = sut.specFileFor(specFor(app.path));

      expect(spec, contains('Name: example'));
      expect(spec, contains('Version: 1.2.3'));
      expect(spec, contains('BuildArch: x86_64'));
      expect(spec, contains('Requires: gtk3'));
      expect(spec, contains('URL: https://example.com'));
      expect(spec, contains('/usr/lib/example'));
    });

    test('the spec should disable the build id links rpm adds by default', () {
      const RpmBundler sut = RpmBundler(runner: _NoopRunner());

      expect(
        sut.specFileFor(specFor(app.path)),
        contains('_build_id_links none'),
        reason:
            'rpm tries to create build-id symlinks for stripped binaries and '
            'fails on a Flutter bundle it did not compile',
      );
    });

    test('the file name should follow the rpm convention', () {
      const RpmBundler sut = RpmBundler(runner: _NoopRunner());

      expect(sut.fileNameFor(specFor(app.path)), 'example-1.2.3-1.x86_64.rpm');
    });

    test('bundle should refuse a build directory that is not there', () async {
      const RpmBundler sut = RpmBundler(runner: _NoopRunner());

      await expectLater(
        sut.bundle(specFor(p.join(root.path, 'missing'))),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('rpmbuild should produce a package the system rpm can read', () async {
      final ProcessResult which = Process.runSync('which', <String>[
        'rpmbuild',
      ]);
      if (which.exitCode != 0) {
        markTestSkipped('rpmbuild is not installed');
        return;
      }

      final String architecture = Process.runSync('rpm', <String>[
        '--eval',
        '%{_arch}',
      ]).stdout.toString().trim();
      if (architecture.isEmpty) {
        markTestSkipped('rpm could not report its own architecture');
        return;
      }

      final RpmBundler sut = RpmBundler(
        runner: const SystemProcessRunner(),
        arch: TargetArch.parse(architecture),
      );
      final String rpm = await sut.bundle(specFor(app.path));

      expect(File(rpm).existsSync(), true);

      final ProcessResult queried = Process.runSync('rpm', <String>[
        '-qp',
        '--queryformat',
        '%{NAME} %{VERSION} %{ARCH}',
        rpm,
      ]);
      expect(queried.exitCode, 0, reason: queried.stderr.toString());
      expect(
        queried.stdout.toString(),
        'example 1.2.3 ${TargetArch.parse(architecture).rpm}',
      );

      final ProcessResult listed = Process.runSync('rpm', <String>[
        '-qlp',
        rpm,
      ]);
      expect(listed.stdout.toString(), contains('/usr/lib/example/example'));
      expect(
        listed.stdout.toString(),
        contains('/usr/share/applications/com.example.app.desktop'),
      );
    });

    test(
      'an architecture nothing here builds should be refused before rpmbuild',
      () {
        for (final String rejected in <String>[
          'sparc64',
          'ppc64le',
          'i686',
          'armv7',
        ]) {
          expect(
            () => TargetArch.parse(rejected),
            throwsA(isA<BundleFailure>()),
            reason:
                'passing it as a free string used to reach rpmbuild and fail '
                'there; the type moves that refusal to the boundary',
          );
        }
      },
    );

    test('every arch should carry the spelling each tool prints', () {
      expect(TargetArch.x86_64.debian, 'amd64');
      expect(TargetArch.x86_64.rpm, 'x86_64');
      expect(TargetArch.x86_64.wix, 'x64');
      expect(TargetArch.arm64.debian, 'arm64');
      expect(TargetArch.arm64.rpm, 'aarch64');
      expect(TargetArch.arm64.wix, 'arm64');
    });

    test('intel and amd should resolve to one target, not two', () {
      expect(TargetArch.parse('intel'), TargetArch.x86_64);
      expect(TargetArch.parse('amd64'), TargetArch.x86_64);
      expect(TargetArch.parse('x86_64'), TargetArch.x86_64);
      expect(TargetArch.parse('x64'), TargetArch.x86_64);
    });

    test('the rust triple should name the target cargo needs', () {
      expect(
        TargetArch.arm64.rustTriple(TargetOs.windows),
        'aarch64-pc-windows-msvc',
      );
      expect(
        TargetArch.x86_64.rustTriple(TargetOs.linux),
        'x86_64-unknown-linux-gnu',
      );
      expect(
        TargetArch.arm64.rustTriple(TargetOs.macos),
        'aarch64-apple-darwin',
      );
    });

    test('a deb and an rpm for arm should not share a spelling', () {
      expect(const DebBundler(arch: TargetArch.arm64).architecture, 'arm64');
      expect(
        const RpmBundler(
          runner: SystemProcessRunner(),
          arch: TargetArch.arm64,
        ).architecture,
        'aarch64',
        reason:
            'the free-string era mapped amd64 to x86_64 by hand and left '
            'arm64 alone, which wrote BuildArch: arm64 into the spec',
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
