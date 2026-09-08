import 'dart:io';

final class SessionBus {
  const SessionBus({
    required this.environment,
    required this.onLinux,
    this.exists = _onDisk,
  });

  final Map<String, String> environment;
  final bool onLinux;
  final bool Function(String path) exists;

  static const String _address = 'DBUS_SESSION_BUS_ADDRESS';
  static const String _runtime = 'XDG_RUNTIME_DIR';

  bool get reachable {
    if (!onLinux) {
      return true;
    }
    if ((environment[_address] ?? '').trim().isNotEmpty) {
      return true;
    }
    final String runtime = (environment[_runtime] ?? '').trim();
    return runtime.isNotEmpty && exists('$runtime/bus');
  }

  String get absentBecause =>
      'this Linux session has no D-Bus session bus, so the desktop has no '
      'notification service to register with. $_address is unset and there is '
      'no socket at \$$_runtime/bus. That is what a container, an ssh login '
      'and a bare kiosk look like.';

  static bool _onDisk(String path) =>
      FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
}
