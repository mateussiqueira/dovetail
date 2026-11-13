import 'dart:io';

Future<ProcessResult> runPackageTool(
  String runner,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) => Process.run(
  _executable(runner, environment),
  arguments,
  workingDirectory: workingDirectory,
  environment: environment,
  runInShell: Platform.isWindows && runner == 'flutter',
);

ProcessResult runPackageToolSync(
  String runner,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) => Process.runSync(
  _executable(runner, environment),
  arguments,
  workingDirectory: workingDirectory,
  environment: environment,
  runInShell: Platform.isWindows && runner == 'flutter',
);

String _executable(String runner, Map<String, String>? environment) {
  if (!Platform.isWindows) return runner;
  if (runner == 'flutter') return 'flutter.bat';
  if (runner != 'bash') return runner;
  final ProcessResult found = Process.runSync('where.exe', <String>[
    'bash.exe',
  ], environment: environment);
  return selectNativeBashExecutable(
    found.stdout.toString().split(RegExp(r'\r?\n')),
    Platform.environment['SystemRoot']!,
  );
}

String selectNativeBashExecutable(Iterable<String> candidates, String windows) {
  final String wsl = '$windows/System32/bash.exe'
      .replaceAll(r'\', '/')
      .toLowerCase();
  for (final String candidate in candidates) {
    if (candidate.isNotEmpty &&
        candidate.replaceAll(r'\', '/').toLowerCase() != wsl) {
      return candidate;
    }
  }
  throw const ProcessException(
    'bash',
    <String>[],
    'Git Bash is required to check a Windows Git worktree; the WSL launcher cannot be used.',
  );
}
