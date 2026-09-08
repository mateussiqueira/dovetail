import 'package:dovetail_platform_channel/dovetail_platform_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SessionBus busWith(
    Map<String, String> environment, {
    bool onLinux = true,
    Set<String> onDisk = const <String>{},
  }) => SessionBus(
    environment: environment,
    onLinux: onLinux,
    exists: onDisk.contains,
  );

  test('an address in the environment should be enough', () {
    expect(
      busWith(<String, String>{
        'DBUS_SESSION_BUS_ADDRESS': 'unix:path=/run/user/1000/bus',
      }).reachable,
      true,
    );
  });

  test('a socket under the runtime directory should be enough', () {
    expect(
      busWith(
        <String, String>{'XDG_RUNTIME_DIR': '/run/user/1000'},
        onDisk: <String>{'/run/user/1000/bus'},
      ).reachable,
      true,
    );
  });

  test('a runtime directory with no socket in it is not a bus', () {
    expect(
      busWith(<String, String>{'XDG_RUNTIME_DIR': '/run/user/1000'}).reachable,
      false,
      reason:
          'XDG_RUNTIME_DIR is set in a container that has no dbus at all, so '
          'the variable alone says nothing',
    );
  });

  test('an empty address should not count as an address', () {
    expect(
      busWith(<String, String>{'DBUS_SESSION_BUS_ADDRESS': '   '}).reachable,
      false,
    );
  });

  test('nothing at all should mean no bus', () {
    expect(busWith(const <String, String>{}).reachable, false);
  });

  test('off Linux the question does not apply', () {
    expect(
      busWith(const <String, String>{}, onLinux: false).reachable,
      true,
      reason:
          'macOS and Windows reach their notification service without D-Bus, '
          'so an absent bus there is not a reason to refuse',
    );
  });

  test('the reason should name both places it looked', () {
    final SessionBus sut = busWith(const <String, String>{});

    expect(sut.absentBecause, contains('DBUS_SESSION_BUS_ADDRESS'));
    expect(sut.absentBecause, contains('XDG_RUNTIME_DIR'));
  });
}
