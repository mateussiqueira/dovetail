import 'dart:io';

import 'package:dovetail_cli/src/diagnostic/cli_log.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory home;
  late CliLog log;

  setUp(() {
    home = Directory.systemTemp.createTempSync('dovetail_cli_log');
    log = CliLog(home: home.path);
  });

  tearDown(() => home.deleteSync(recursive: true));

  List<String> lines() => File(log.path)
      .readAsStringSync()
      .split('\n')
      .where((String line) => line.isNotEmpty)
      .toList();

  group('record', () {
    test('writes one line with a timestamp and the failure', () {
      log.record(
        runtimeType: 'StateError',
        message: 'boom',
        stack: StackTrace.fromString('at a\nat b'),
      );

      final String text = File(log.path).readAsStringSync();
      expect(text, contains('StateError'));
      expect(text, contains('boom'));
      expect(text, matches(RegExp(r'^\d{4}-\d{2}-\d{2}T')));
      expect(text, contains('at a'));
      expect(text, contains('at b'));
    });

    test('a second entry appends a second line, one entry per line', () {
      log.record(runtimeType: 'StateError', message: 'first');
      log.record(runtimeType: 'ArgumentError', message: 'second');

      final List<String> written = lines();
      expect(written, hasLength(2));
      expect(written[0], contains('first'));
      expect(written[1], contains('second'));
    });

    test('caps the stack to the configured line count', () {
      final CliLog capped = CliLog(home: home.path, maxStackLines: 3);
      final String frames = List<String>.generate(
        10,
        (int i) => 'frame$i',
      ).join('\n');

      capped.record(
        runtimeType: 'X',
        message: 'm',
        stack: StackTrace.fromString(frames),
      );

      final String text = File(capped.path).readAsStringSync();
      expect(text, contains('frame0'));
      expect(text, contains('frame2'));
      expect(text, isNot(contains('frame3')));
    });
  });

  group('rotation', () {
    test('rotates to .old and starts fresh when the cap is reached', () {
      final CliLog rotating = CliLog(home: home.path, maxBytes: 200);
      for (int i = 0; i < 20; i++) {
        rotating.record(
          runtimeType: 'Error',
          message: 'entry $i with some padding text',
        );
      }

      final File active = File(rotating.path);
      final File previous = File('${rotating.path}.old');
      expect(previous.existsSync(), isTrue);
      expect(active.existsSync(), isTrue);
      expect(
        active.lengthSync(),
        lessThanOrEqualTo(rotating.maxBytes),
        reason: 'o arquivo ativo nunca passa do teto',
      );
    });
  });

  group('silent safety', () {
    test('never throws when the log directory cannot be created', () {
      File(p.join(home.path, 'log')).writeAsStringSync('i am a file');

      expect(() => log.record(runtimeType: 'X', message: 'm'), returnsNormally);
    });
  });
}
