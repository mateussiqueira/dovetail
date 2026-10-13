import 'dart:convert';
import 'dart:io';

import 'package:dovetail_store/dovetail_store.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late String path;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('dovetail_store_');
    path = '${directory.path}/store.json';
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('a store that does not exist yet should open empty', () {
    final KeyValueStore store = KeyValueStore.open(path);

    expect(store.keys, isEmpty);
    expect(File(path).existsSync(), isFalse);
  });

  test('a value set should still be there after reopening', () {
    KeyValueStore.open(path).set('theme', 'dark');

    expect(KeyValueStore.open(path).get('theme'), 'dark');
  });

  test('every JSON value should come back as it went in', () {
    final KeyValueStore store = KeyValueStore.open(path);
    store.set('window', <String, Object?>{
      'x': 1,
      'scale': 1.5,
      'maximized': false,
      'title': null,
      'tabs': <Object?>['a', 'b'],
    });
    store.set('theme', 'dark');

    final KeyValueStore reopened = KeyValueStore.open(path);

    expect(reopened.keys, <String>['window', 'theme']);
    expect(reopened.get('window'), <String, Object?>{
      'x': 1,
      'scale': 1.5,
      'maximized': false,
      'title': null,
      'tabs': <Object?>['a', 'b'],
    });
  });

  test('a removed key should be gone after reopening', () {
    final KeyValueStore store = KeyValueStore.open(path);
    store.set('theme', 'dark');

    store.remove('theme');

    expect(KeyValueStore.open(path).containsKey('theme'), isFalse);
  });

  test('removing a key that is not there should not write', () {
    KeyValueStore.open(path).remove('theme');

    expect(File(path).existsSync(), isFalse);
  });

  test('a value JSON cannot carry should leave the store as it was', () {
    final KeyValueStore store = KeyValueStore.open(path);
    store.set('theme', 'dark');

    expect(
      () => store.set('clock', DateTime(2026)),
      throwsA(isA<JsonUnsupportedObjectError>()),
    );
    expect(store.containsKey('clock'), isFalse);
    expect(KeyValueStore.open(path).keys, <String>['theme']);
  });

  test('a file that is not a JSON object should be refused', () {
    File(path).writeAsStringSync('["theme"]');

    expect(() => KeyValueStore.open(path), throwsFormatException);
  });

  test(
    'a writer killed in the middle of a set should leave the store whole',
    () async {
      KeyValueStore.open(path).set('theme', 'dark');
      final String marker = '${directory.path}/halfway';

      final Process writer = await Process.start(
        Platform.resolvedExecutable,
        <String>['test/support/interrupted_set.dart', path, marker],
      );
      while (!File(marker).existsSync()) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      writer.kill(ProcessSignal.sigkill);

      expect(await writer.exitCode, -9);
      expect(KeyValueStore.open(path).keys, <String>['theme']);
      expect(KeyValueStore.open(path).get('theme'), 'dark');
      expect(File('$path.tmp').readAsStringSync(), '{"theme":"dark"');
    },
    testOn: '!windows',
  );
}
