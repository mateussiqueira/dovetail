enum MsiPhase {
  beforeInstallFiles('InstallFiles', true),
  afterInstallFiles('InstallFiles', false),
  beforeRemoveFiles('RemoveFiles', true),
  afterRemoveFiles('RemoveFiles', false);

  const MsiPhase(this.anchor, this.before);

  final String anchor;
  final bool before;

  String get sequenceAttribute => before ? 'Before' : 'After';
}

final class MsiPrivilegedStep {
  const MsiPrivilegedStep({
    required this.id,
    required this.phase,
    required this.relativeExecutable,
    this.arguments = const <String>[],
    this.fatalOnFailure = true,
    this.rollbackFor,
    this.failureMessages = const <int, String>{},
  });

  final String id;
  final MsiPhase phase;
  final String relativeExecutable;
  final List<String> arguments;
  final bool fatalOnFailure;
  final String? rollbackFor;
  final Map<int, String> failureMessages;

  bool get isRollback => rollbackFor != null;

  String get commandLine =>
      arguments.isEmpty ? '' : arguments.map(_quote).join(' ');

  static String _quote(String argument) =>
      argument.contains(' ') ? '"$argument"' : argument;
}
