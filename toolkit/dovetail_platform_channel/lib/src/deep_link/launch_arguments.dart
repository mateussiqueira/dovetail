final class LaunchArguments {
  const LaunchArguments._();

  static Iterable<Uri> urisIn(
    List<String> arguments, {
    Set<String> schemes = const <String>{},
  }) sync* {
    for (final String argument in arguments) {
      final Uri? parsed = Uri.tryParse(argument);
      if (parsed == null || !parsed.hasScheme || parsed.scheme.isEmpty) {
        continue;
      }
      if (parsed.scheme == 'file') {
        continue;
      }
      if (schemes.isNotEmpty && !schemes.contains(parsed.scheme)) {
        continue;
      }
      yield parsed;
    }
  }
}
