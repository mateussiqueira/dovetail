import 'dart:async';
import 'dart:io';

import 'package:dovetail_log/src/app_log.dart';
import 'package:test/test.dart';

const String _noon = '2026-10-13T12:00:00.000Z';

void main() {
  late Directory directory;
  late String path;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('dovetail_log_');
    path = '${directory.path}/app.log';
  });

  tearDown(() => directory.deleteSync(recursive: true));

  AppLog appLog({int maxBytes = 1024, int keep = 3}) => AppLog(
    path: path,
    maxBytes: maxBytes,
    keep: keep,
    clock: () => DateTime.utc(2026, 10, 13, 12).toLocal(),
  );

  test('a line should be stamped in UTC and end with a newline', () {
    appLog().info('started');

    expect(File(path).readAsStringSync(), '$_noon INFO app: started\n');
  });

  test('each level should name itself', () {
    final AppLog log = appLog();

    log.debug('d');
    log.info('i');
    log.warn('w');
    log.error('e');

    expect(File(path).readAsLinesSync(), <String>[
      '$_noon DEBUG app: d',
      '$_noon INFO app: i',
      '$_noon WARN app: w',
      '$_noon ERROR app: e',
    ]);
  });

  test('a line that lands exactly on the cap should stay in the file', () {
    final AppLog log = appLog(maxBytes: 74);

    log.info('a');
    log.info('b');

    expect(File(path).lengthSync(), 74);
    expect(File('$path.1').existsSync(), isFalse);
  });

  test('the line that would pass the cap should start a new file', () {
    final AppLog log = appLog(maxBytes: 74);

    log.info('a');
    log.info('b');
    log.info('c');

    expect(File(path).readAsLinesSync(), <String>['$_noon INFO app: c']);
    expect(File('$path.1').readAsLinesSync(), <String>[
      '$_noon INFO app: a',
      '$_noon INFO app: b',
    ]);
  });

  test('rotation should keep only the newest files', () {
    final AppLog log = appLog(maxBytes: 37, keep: 2);

    for (final String each in <String>['a', 'b', 'c', 'd']) {
      log.info(each);
    }

    expect(File(path).readAsLinesSync(), <String>['$_noon INFO app: d']);
    expect(File('$path.1').readAsLinesSync(), <String>['$_noon INFO app: c']);
    expect(File('$path.2').readAsLinesSync(), <String>['$_noon INFO app: b']);
    expect(File('$path.3').existsSync(), isFalse);
  });

  test('a line longer than the cap should still be written whole', () {
    appLog(maxBytes: 10).info('longer than the cap');

    expect(File(path).readAsLinesSync(), <String>[
      '$_noon INFO app: longer than the cap',
    ]);
    expect(File('$path.1').existsSync(), isFalse);
  });

  test('lines from a stream should land in the same file, in order', () async {
    final AppLog log = appLog();
    final StreamController<String> rust = StreamController<String>();
    final Future<void> drained = log.attach(rust.stream).asFuture<void>();

    log.info('from dart');
    rust.add('WARN core: from rust');
    await rust.close();
    await drained;

    expect(File(path).readAsLinesSync(), <String>[
      '$_noon INFO app: from dart',
      '$_noon WARN core: from rust',
    ]);
  });

  test('a directory that does not exist yet should be created', () {
    path = '${directory.path}/logs/today/app.log';

    appLog().info('started');

    expect(File(path).existsSync(), isTrue);
  });

  test('keeping no rotated file should be refused', () {
    expect(() => appLog(keep: 0), throwsArgumentError);
  });
}
