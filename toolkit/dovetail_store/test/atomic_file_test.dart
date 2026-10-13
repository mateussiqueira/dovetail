import 'dart:convert';
import 'dart:io';

import 'package:dovetail_store/src/atomic_file.dart';
import 'package:test/test.dart';

Iterable<List<int>> _halfThenFail() sync* {
  yield utf8.encode('{"new":');
  throw const FormatException('the producer gave up');
}

void main() {
  late Directory directory;
  late String path;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('dovetail_store_');
    path = '${directory.path}/store.json';
  });

  tearDown(() => directory.deleteSync(recursive: true));

  group('a write', () {
    test('should replace the whole content', () {
      File(path).writeAsStringSync('{"old":"a longer value"}');

      AtomicFile(path).write(<List<int>>[utf8.encode('{}')]);

      expect(File(path).readAsStringSync(), '{}');
    });

    test('should leave no temporary file behind', () {
      AtomicFile(path).write(<List<int>>[utf8.encode('{}')]);

      expect(File('$path.tmp').existsSync(), isFalse);
    });

    test('should not be blocked by a temporary file a dead writer left', () {
      File('$path.tmp').writeAsStringSync('{"left":"by a writer that died"}');

      AtomicFile(path).write(<List<int>>[utf8.encode('{}')]);

      expect(File(path).readAsStringSync(), '{}');
    });

    test('should sync the directory after the rename, not before', () {
      final List<String> seen = <String>[];

      AtomicFile(
        path,
        syncDirectory: (String synced) => seen
          ..add(synced)
          ..add(File(path).readAsStringSync()),
      ).write(<List<int>>[utf8.encode('{}')]);

      expect(seen, <String>[directory.path, '{}']);
    });
  });

  group('a write that fails halfway', () {
    test('should keep the old content', () {
      File(path).writeAsStringSync('{"old":true}');

      expect(
        () => AtomicFile(path).write(_halfThenFail()),
        throwsFormatException,
      );
      expect(File(path).readAsStringSync(), '{"old":true}');
    });

    test('should remove its temporary file', () {
      expect(
        () => AtomicFile(path).write(_halfThenFail()),
        throwsFormatException,
      );
      expect(File('$path.tmp').existsSync(), isFalse);
    });
  });

  test('a file that does not exist should read as null', () {
    expect(AtomicFile(path).read(), isNull);
  });

  group('fsyncDirectory', () {
    test('should sync a directory that exists', () {
      expect(() => AtomicFile.fsyncDirectory(directory.path), returnsNormally);
    });

    test('should refuse a directory that does not exist', () {
      expect(
        () => AtomicFile.fsyncDirectory('${directory.path}/missing'),
        throwsA(
          isA<FileSystemException>().having(
            (FileSystemException error) => error.message,
            'message',
            'cannot open the directory to sync',
          ),
        ),
      );
    }, testOn: '!windows');
  });
}
