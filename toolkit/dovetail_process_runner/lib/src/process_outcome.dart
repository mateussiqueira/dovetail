/// What a finished process left behind: exit code and both streams,
/// captured whole.
///
/// Built by [ProcessRunner.run]; a caller reads [succeeded] first and
/// [firstDiagnostic] when it did not.
final class ProcessOutcome {
  const ProcessOutcome({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// The code the process exited with; `0` is success by convention.
  final int exitCode;

  /// Everything the process wrote to its standard output.
  final String stdout;

  /// Everything the process wrote to its standard error.
  final String stderr;

  /// Whether the exit code was `0`.
  bool get succeeded => exitCode == 0;

  /// The first non-empty line of stderr, falling back to stdout, falling
  /// back to the exit code.
  ///
  /// For a message that names the failure in one line without pasting a
  /// whole build log into it.
  String get firstDiagnostic {
    final String text = stderr.trim().isEmpty ? stdout : stderr;
    final Iterable<String> lines = text
        .split('\n')
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty);
    return lines.isEmpty ? 'exit code $exitCode' : lines.first;
  }

  @override
  String toString() =>
      'ProcessOutcome(exitCode: $exitCode, '
      'stdout: ${stdout.length}B, stderr: ${stderr.length}B)';
}
