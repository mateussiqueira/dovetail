abstract interface class LaunchAtLogin {
  Future<bool> isEnabled();
  Future<void> enable();
  Future<void> disable();
}
