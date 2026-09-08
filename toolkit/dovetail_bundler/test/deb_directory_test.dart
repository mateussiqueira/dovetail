import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late String app;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_debdirs');
    app = p.join(root.path, 'stage');
    Directory(app).createSync(recursive: true);
    File(p.join(app, 'client')).writeAsStringSync('#!/bin/sh\nexec true\n');
    Directory(
      p.join(app, 'data', 'flutter_assets'),
    ).createSync(recursive: true);
    File(
      p.join(app, 'data', 'flutter_assets', 'AssetManifest.json'),
    ).writeAsStringSync('{}');
    Directory(p.join(app, 'lib')).createSync();
    File(p.join(app, 'lib', 'libapp.so')).writeAsStringSync('so');
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

  group('the deb directory tree', () {
    test('every file should be preceded by an entry for each parent', () async {
      final Archive data = dataOf(await const DebBundler().bundle(specOf()));
      final List<String> order = data.files
          .map((ArchiveFile member) => member.name)
          .toList();

      for (final ArchiveFile member in data.files.where(
        (ArchiveFile entry) => entry.isFile,
      )) {
        String walked = '';
        for (final String segment in p.posix.split(
          p.posix.dirname(member.name),
        )) {
          walked = walked.isEmpty ? segment : '$walked/$segment';
          expect(
            order.indexOf('$walked/'),
            inInclusiveRange(0, order.indexOf(member.name) - 1),
            reason:
                'dpkg unpacks a data tar in order and creates no directory of '
                'its own, so ${member.name} without an entry for $walked/ '
                'fails the install with No such file or directory',
          );
        }
      }
    });

    test('a directory entry should be traversable and writable', () async {
      final Archive data = dataOf(await const DebBundler().bundle(specOf()));
      final Iterable<ArchiveFile> directories = data.files.where(
        (ArchiveFile entry) => entry.isDirectory,
      );

      expect(directories, isNotEmpty);
      for (final ArchiveFile directory in directories) {
        expect(
          directory.mode & 0x1FF,
          0x1ED,
          reason: '${directory.name} at 644 cannot be entered',
        );
      }
    });

    test('a symlink should survive as a symlink, not vanish', () async {
      Link(p.join(app, 'lib', 'libfoo.so.1')).createSync('libfoo.so.1.2.3');
      File(p.join(app, 'lib', 'libfoo.so.1.2.3')).writeAsStringSync('so');

      final Archive data = dataOf(await const DebBundler().bundle(specOf()));
      final ArchiveFile link = data.files.firstWhere(
        (ArchiveFile entry) => entry.name == 'usr/lib/client/lib/libfoo.so.1',
        orElse: () => throw StateError(
          'the symlink was dropped; a versioned SONAME pair ships as a link '
          'beside the real object, and losing it breaks the loader',
        ),
      );

      expect(link.isSymbolicLink, true);
      expect(link.symbolicLink, 'libfoo.so.1.2.3');
    });

    test('installedName should answer posix separators on any host', () {
      expect(
        DebBundler.installedName(
          p.join('root', 'bundle', 'data', 'flutter_assets', 'x.json'),
          from: p.join('root', 'bundle'),
        ),
        'data/flutter_assets/x.json',
        reason:
            'a tar member named with backslashes installs a file literally '
            'called data\\flutter_assets\\x.json, and the tree is flat',
      );
    });

    test('directoriesFor should name every level, parents first', () {
      expect(
        DebBundler.directoriesFor(<String>[
          'usr/lib/client/lib/libapp.so',
          'usr/share/applications/io.example.client.desktop',
        ]),
        <String>[
          'usr/',
          'usr/lib/',
          'usr/lib/client/',
          'usr/lib/client/lib/',
          'usr/share/',
          'usr/share/applications/',
        ],
      );
    });

    test('directoriesFor should not repeat a shared directory', () {
      expect(
        DebBundler.directoriesFor(<String>['usr/lib/a.so', 'usr/lib/b.so']),
        <String>['usr/', 'usr/lib/'],
      );
    });
  });
}
