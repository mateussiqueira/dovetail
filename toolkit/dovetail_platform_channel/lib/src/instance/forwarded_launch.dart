final class ForwardedLaunch {
  const ForwardedLaunch({
    required this.workingDirectory,
    required this.arguments,
  });

  final String workingDirectory;
  final List<String> arguments;

  @override
  String toString() =>
      'ForwardedLaunch($workingDirectory, ${arguments.join(' ')})';
}
