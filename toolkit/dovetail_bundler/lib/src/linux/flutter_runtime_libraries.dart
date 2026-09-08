abstract final class FlutterRuntimeLibraries {
  static const List<String> debian = <String>['libegl1', 'libgles2'];

  static const List<String> rpm = <String>['libglvnd-egl', 'libglvnd-gles'];

  static const String because =
      'the Flutter engine opens libEGL.so.1 and libGLESv2.so.2 with dlopen, '
      'so they are absent from the ELF and no dependency scanner can find '
      'them. A package without them installs and the app aborts before its '
      'first frame.';
}
