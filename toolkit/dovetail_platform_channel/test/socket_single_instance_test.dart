import 'dart:io';

import 'package:dovetail_platform_channel/dovetail_platform_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  final List<SocketSingleInstance> opened = <SocketSingleInstance>[];

  SocketSingleInstance instance(String key) {
    final SocketSingleInstance created = SocketSingleInstance(
      instanceKey: key,
      directory: root.path,
    );
    opened.add(created);
    return created;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_si');
  });

  tearDown(() async {
    for (final SocketSingleInstance created in opened) {
      await created.release().catchError((Object _) {});
    }
    opened.clear();
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  test(
    'the first claim should become the primary and open the socket',
    () async {
      final SocketSingleInstance sut = instance('com.example.app');

      expect(await sut.claim(), SingleInstanceVerdict.primary);
      expect(File(sut.socketPath).existsSync(), true);
    },
  );

  test(
    'the second claim should become secondary, not a second primary',
    () async {
      await instance('com.example.app').claim();

      expect(
        await instance('com.example.app').claim(),
        SingleInstanceVerdict.secondary,
      );
    },
  );

  test(
    'the primary should receive the arguments the second launch carried',
    () async {
      final SocketSingleInstance primary = instance('com.example.app');
      await primary.claim();
      final Future<ForwardedLaunch> forwarded = primary.launches().first;

      await instance('com.example.app').claim(
        arguments: <String>['myid://activate/abc123'],
        workingDirectory: '/home/user',
      );

      final ForwardedLaunch launch = await forwarded;
      expect(launch.arguments, <String>['myid://activate/abc123']);
      expect(launch.workingDirectory, '/home/user');
    },
  );

  test('a deep link arriving at an open app is exactly this path', () async {
    final SocketSingleInstance primary = instance('com.example.app');
    await primary.claim();
    final Future<ForwardedLaunch> forwarded = primary.launches().first;

    await instance(
      'com.example.app',
    ).claim(arguments: <String>['--quiet', 'myid://pair/9f2c']);

    expect((await forwarded).arguments.last, 'myid://pair/9f2c');
  });

  test(
    'a stale socket left by a crash should not block the next launch',
    () async {
      final SocketSingleInstance first = instance('com.example.app');
      await first.claim();
      final String path = first.socketPath;
      await first.release();
      File(path).writeAsStringSync('');
      expect(File(path).existsSync(), true);

      final SocketSingleInstance sut = instance('com.example.app');

      expect(await sut.claim(), SingleInstanceVerdict.primary);
    },
  );

  test('two different keys should not see each other', () async {
    await instance('com.example.alpha').claim();

    expect(
      await instance('com.example.beta').claim(),
      SingleInstanceVerdict.primary,
    );
  });

  test('the socket name should survive a key with dots and dashes', () {
    final SocketSingleInstance sut = instance('com.example.my-app');

    expect(sut.socketPath, contains('com_example_my_app_si.sock'));
    expect(sut.socketPath.length, lessThan(104));
  });

  test('a payload with no separator should still yield a directory', () {
    final ForwardedLaunch launch = SocketSingleInstance.decode('/tmp');

    expect(launch.workingDirectory, '/tmp');
    expect(launch.arguments, isEmpty);
  });

  test('release should remove the socket so the path is free', () async {
    final SocketSingleInstance sut = instance('com.example.app');
    await sut.claim();

    await sut.release();

    expect(File(sut.socketPath).existsSync(), false);
  });
}
