import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late String app;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_payload');
    app = p.join(root.path, 'stage');
    Directory(app).createSync(recursive: true);
    _write(p.join(app, 'client'), '#!/bin/sh\nexec true\n', mode: '755');
    _write(p.join(app, 'data.bin'), 'x');
    _write(p.join(app, 'lib', 'core.so'), 'so', mode: '755');
  });

  tearDown(() => root.deleteSync(recursive: true));

  BundleSpec specWith({List<StagedFile> extra = const <StagedFile>[]}) =>
      BundleSpec(
        productName: 'Example',
        manufacturer: 'Example Ltda',
        identifier: 'io.example.client',
        version: AppVersion.parse('1.0.0'),
        mainBinaryName: 'client',
        appDirectory: app,
        outputDirectory: p.join(root.path, 'out'),
        extraFiles: extra,
      );

  Archive dataOf(String deb) {
    final ProcessResult extracted = Process.runSync('ar', <String>[
      'p',
      deb,
      'data.tar.gz',
    ], stdoutEncoding: null);
    expect(extracted.exitCode, 0, reason: extracted.stderr.toString());
    return TarDecoder().decodeBytes(
      const GZipDecoder().decodeBytes(extracted.stdout as List<int>),
    );
  }

  ArchiveFile fileNamed(Archive archive, String name) =>
      archive.files.firstWhere((ArchiveFile file) => file.name == name);

  group('the deb payload', () {
    test('an executable should stay executable after packaging', () async {
      final Archive data = dataOf(await const DebBundler().bundle(specWith()));
      expect(
        fileNamed(data, 'usr/lib/client/client').mode & 0x49,
        0x49,
        reason:
            'the .desktop Exec points at this file; installed 644 it cannot '
            'run, and dpkg reports nothing',
      );
    });

    test('a data file should not become executable', () async {
      final Archive data = dataOf(await const DebBundler().bundle(specWith()));
      expect(fileNamed(data, 'usr/lib/client/data.bin').mode & 0x49, 0);
    });

    test('a nested executable should keep its mode too', () async {
      final Archive data = dataOf(await const DebBundler().bundle(specWith()));
      expect(fileNamed(data, 'usr/lib/client/lib/core.so').mode & 0x49, 0x49);
    });

    test('the desktop entry should be readable and not executable', () async {
      final Archive data = dataOf(await const DebBundler().bundle(specWith()));
      expect(
        fileNamed(
              data,
              'usr/share/applications/io.example.client.desktop',
            ).mode &
            0x49,
        0,
      );
    });

    test('a staged file should be installed where it was staged', () async {
      final String helper = p.join(root.path, 'privileged-helper');
      _write(helper, '#!/bin/sh\n', mode: '755');

      final Archive data = dataOf(
        await const DebBundler().bundle(
          specWith(
            extra: <StagedFile>[
              StagedFile(
                source: helper,
                destination: 'usr/lib/client/privileged-helper',
              ),
            ],
          ),
        ),
      );

      final ArchiveFile staged = fileNamed(
        data,
        'usr/lib/client/privileged-helper',
      );
      expect(staged.mode & 0x49, 0x49);
    });

    test(
      'a leading slash on the destination should not create an empty dir',
      () async {
        final String extra = p.join(root.path, 'policy.xml');
        _write(extra, '<x/>');

        final Archive data = dataOf(
          await const DebBundler().bundle(
            specWith(
              extra: <StagedFile>[
                StagedFile(
                  source: extra,
                  destination: '/usr/share/example/policy.xml',
                ),
              ],
            ),
          ),
        );
        expect(
          data.files.map((ArchiveFile file) => file.name),
          contains('usr/share/example/policy.xml'),
        );
      },
    );

    test('a staged file that is not on disk should be refused', () async {
      await expectLater(
        const DebBundler().bundle(
          specWith(
            extra: <StagedFile>[
              StagedFile(
                source: p.join(root.path, 'never-built'),
                destination: 'usr/lib/client/never-built',
              ),
            ],
          ),
        ),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.remedy,
            'remedy',
            contains('silently drops'),
          ),
        ),
      );
    });
  });

  group('the rpm spec', () {
    test('a staged file should be declared in %files', () {
      final String helper = p.join(root.path, 'privileged-helper');
      _write(helper, '#!/bin/sh\n', mode: '755');

      final String text = const RpmBundler(runner: SystemProcessRunner())
          .specFileFor(
            specWith(
              extra: <StagedFile>[
                StagedFile(
                  source: helper,
                  destination: 'usr/lib/client/privileged-helper',
                ),
              ],
            ),
          );
      expect(text, contains('/usr/lib/client/privileged-helper'));
    });

    test('a destination already absolute should not be doubled', () {
      final String extra = p.join(root.path, 'policy.xml');
      _write(extra, '<x/>');

      final String text = const RpmBundler(runner: SystemProcessRunner())
          .specFileFor(
            specWith(
              extra: <StagedFile>[
                StagedFile(
                  source: extra,
                  destination: '/usr/share/example/policy.xml',
                ),
              ],
            ),
          );
      expect(text, contains('/usr/share/example/policy.xml'));
      expect(text, isNot(contains('//usr')));
    });
  });

  group('the dmg', () {
    test('should refuse staged files rather than drop them', () async {
      final String extra = p.join(root.path, 'README.txt');
      _write(extra, 'hello');
      final String bundle = p.join(root.path, 'Example.app');
      Directory(bundle).createSync();

      await expectLater(
        const DmgBundler(runner: SystemProcessRunner()).bundle(
          BundleSpec(
            productName: 'Example',
            manufacturer: 'Example Ltda',
            identifier: 'io.example.client',
            version: AppVersion.parse('1.0.0'),
            mainBinaryName: 'client',
            appDirectory: bundle,
            outputDirectory: p.join(root.path, 'out'),
            extraFiles: <StagedFile>[
              StagedFile(source: extra, destination: 'README.txt'),
            ],
          ),
        ),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.remedy,
            'remedy',
            contains('inside the bundle'),
          ),
        ),
        reason:
            'nsis and msi honour extraFiles; a dmg that ignored them would '
            'ship a Windows package with the helper and a macOS one without',
      );
    });
  });
}

void _write(String path, String content, {String? mode}) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
  if (mode != null) {
    Process.runSync('chmod', <String>[mode, path]);
  }
}
