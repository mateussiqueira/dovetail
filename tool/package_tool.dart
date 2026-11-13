import 'dart:io';

Future<ProcessResult> runPackageTool(
  String runner,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) => Process.run(
  _executable(runner),
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
  _executable(runner),
  arguments,
  workingDirectory: workingDirectory,
  environment: environment,
  runInShell: Platform.isWindows && runner == 'flutter',
);

String _executable(String runner) =>
    Platform.isWindows && runner == 'flutter' ? 'flutter.bat' : runner;
