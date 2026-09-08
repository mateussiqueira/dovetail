/// Thrown by [ProcessRunner.run] when a child outlives its [limit] and
/// is killed.
///
/// Carries the output captured until then, because a hung child says
/// nothing at the moment it hangs — what it printed before is the clue.
final class ProcessTimeout implements Exception {
  const ProcessTimeout({
    required this.executable,
    required this.limit,
    required this.stdout,
    required this.stderr,
  });

  /// The program that was killed.
  final String executable;

  /// How long it was allowed to run.
  final Duration limit;

  /// Standard output captured before the kill.
  final String stdout;

  /// Standard error captured before the kill.
  final String stderr;

  @override
  String toString() =>
      '$executable did not finish within ${limit.inSeconds}s and was killed. '
      'A child that hangs holds the whole pipeline with no output to say why; '
      'what it had printed by then follows.\n'
      '${stderr.trim().isEmpty ? stdout.trim() : stderr.trim()}';
}
