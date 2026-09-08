import 'package:dovetail_platform_channel/dovetail_platform_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the binding should report unavailable off Windows', () {
    final WindowsSingleInstance sut = WindowsSingleInstance(
      instanceKey: 'io.example.client',
    );

    expect(sut.isAvailable, false);
    expect(sut.takeForwardedLaunch(), null);
  });

  test('the native verdict codes should map to the Dart enum', () {
    final WindowsSingleInstance sut = WindowsSingleInstance(
      instanceKey: 'io.example.client',
    );

    expect(sut.readVerdict(0), SingleInstanceVerdict.primary);
    expect(sut.readVerdict(1), SingleInstanceVerdict.secondary);
  });

  test('an unavailable guard should let the app run, and say so', () {
    final WindowsSingleInstance sut = WindowsSingleInstance(
      instanceKey: 'io.example.client',
    );

    expect(sut.readVerdict(2), SingleInstanceVerdict.unavailable);
    expect(
      sut.readVerdict(2).mayRun,
      true,
      reason:
          'if the guard cannot run the app still has to open; refusing to '
          'start because a mutex could not be created would be worse than two '
          'windows',
    );
    expect(
      sut.readVerdict(2).isGuarded,
      false,
      reason:
          'answering primary here would claim a guard that is not there, and '
          'the caller would trust a verdict nothing enforces',
    );
  });

  test(
    'claim should answer unavailable where the library is missing',
    () async {
      final WindowsSingleInstance sut = WindowsSingleInstance(
        instanceKey: 'io.example.client',
      );

      expect(await sut.claim(), SingleInstanceVerdict.unavailable);
      await sut.release();
    },
  );

  test('the forwarded stream should stay open with no library', () async {
    final WindowsSingleInstance sut = WindowsSingleInstance(
      instanceKey: 'io.example.client',
    );
    addTearDown(sut.dispose);

    expect(sut.launches(), isA<Stream<ForwardedLaunch>>());
    sut.drain();
  });

  test('draining with nobody listening should leave the queue alone', () {
    final WindowsSingleInstance sut = WindowsSingleInstance(
      instanceKey: 'io.example.client',
    );
    addTearDown(sut.dispose);

    sut.drain();

    expect(
      sut.launches(),
      isA<Stream<ForwardedLaunch>>(),
      reason:
          'a broadcast controller with no subscriber discards what is added '
          'to it, and the native queue is the only buffer in the path: the '
          'poll starts at claim and the app subscribes a frame later, so '
          'draining early throws the forwarded launch away',
    );
  });

  test('decode should split the working directory from the arguments', () {
    final ForwardedLaunch launch = WindowsSingleInstance.decode(
      'C:\\Users\\x\u0000\u0000--quiet\u0000myid://pair/9f2c',
    );

    expect(launch.workingDirectory, r'C:\Users\x');
    expect(launch.arguments, <String>['--quiet', 'myid://pair/9f2c']);
  });

  test('decode should handle a launch with no arguments', () {
    final ForwardedLaunch launch = WindowsSingleInstance.decode(
      'C:\\Users\\x\u0000\u0000',
    );

    expect(launch.workingDirectory, r'C:\Users\x');
    expect(launch.arguments, isEmpty);
  });

  test('decode should survive a payload with no separator', () {
    final ForwardedLaunch launch = WindowsSingleInstance.decode(r'C:\Users\x');

    expect(launch.workingDirectory, r'C:\Users\x');
    expect(launch.arguments, isEmpty);
  });

  test(
    'a path with a space should survive, which a space separator would not',
    () {
      final ForwardedLaunch launch = WindowsSingleInstance.decode(
        'C:\\Program Files\\Example\u0000\u0000myid://pair/1',
      );

      expect(launch.workingDirectory, r'C:\Program Files\Example');
      expect(launch.arguments, <String>['myid://pair/1']);
    },
  );

  test('the wire format should match what the socket guard uses', () {
    const String wire = '/home/user\u0000\u0000a\u0000b';
    final ForwardedLaunch fromWindows = WindowsSingleInstance.decode(wire);
    final ForwardedLaunch fromSocket = SocketSingleInstance.decode(wire);

    expect(fromWindows.workingDirectory, fromSocket.workingDirectory);
    expect(fromWindows.arguments, fromSocket.arguments);
  });
}
