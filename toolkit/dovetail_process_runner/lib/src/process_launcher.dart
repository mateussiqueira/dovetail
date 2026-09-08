/// Starts a process and lets go of it.
///
/// The counterpart of [ProcessRunner] for children that are meant to
/// outlive the caller — an installer, the app just built — where waiting
/// for the exit code would be waiting for the user.
abstract interface class ProcessLauncher {
  /// Starts [executable] detached and returns its pid. Nothing is read
  /// from it and nothing waits for it.
  Future<int> launch(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });
}
