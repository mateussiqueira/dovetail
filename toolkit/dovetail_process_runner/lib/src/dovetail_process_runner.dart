import 'package:dovetail_process_runner/src/process_outcome.dart';

/// Runs a process to completion and returns what it produced.
///
/// The seam every build and signing tool in the toolkit goes through: a
/// test hands in a fake and asserts on the arguments; production uses
/// [SystemProcessRunner].
abstract interface class ProcessRunner {
  /// Runs [executable] with [arguments] and waits for it to exit.
  ///
  /// [stdin], when given, is written and closed before waiting. With a
  /// [timeout], a child still running at the deadline is killed and
  /// [ProcessTimeout] is thrown with whatever it had printed.
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdin,
    Duration? timeout,
  });
}
