import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dovetail_process_runner/src/process_launcher.dart';
import 'package:dovetail_process_runner/src/process_outcome.dart';
import 'package:dovetail_process_runner/src/dovetail_process_runner.dart';
import 'package:dovetail_process_runner/src/process_timeout.dart';

/// The [ProcessRunner] and [ProcessLauncher] backed by `dart:io`.
///
/// Streams both outputs as they arrive when [onStdout] or [onStderr] is
/// set, and still returns them whole in the [ProcessOutcome].
final class SystemProcessRunner implements ProcessRunner, ProcessLauncher {
  /// A runner that buffers silently unless a chunk callback is given.
  const SystemProcessRunner({this.onStdout, this.onStderr});

  /// Chamado com cada pedaço assim que chega, antes de o resultado bufferizado
  /// existir. Um filho que roda por minutos — `flutter build`, `notarytool
  /// --wait` — e cujo silêncio até o exit parece travamento é o motivo. O
  /// resultado continua inteiro: o pedaço é repassado E guardado.
  final void Function(String chunk)? onStdout;

  /// Called with each stderr chunk as it arrives; see [onStdout].
  final void Function(String chunk)? onStderr;

  /// Repassa o filho ao stdout e stderr deste processo conforme ele fala.
  static const SystemProcessRunner echoing = SystemProcessRunner(
    onStdout: _toStdout,
    onStderr: _toStderr,
  );

  static void _toStdout(String chunk) => stdout.write(chunk);
  static void _toStderr(String chunk) => stderr.write(chunk);

  /// How long, after killing a child on timeout, the streams are given to
  /// deliver what was already in flight before the exception is thrown.
  static const Duration drainGrace = Duration(milliseconds: 250);

  @override
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdin,
    Duration? timeout,
  }) async {
    final Process process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: false,
    );

    final List<String> out = <String>[];
    final List<String> err = <String>[];
    final Future<void> draining = Future.wait(<Future<void>>[
      process.stdout.transform(utf8.decoder).forEach((String chunk) {
        out.add(chunk);
        onStdout?.call(chunk);
      }),
      process.stderr.transform(utf8.decoder).forEach((String chunk) {
        err.add(chunk);
        onStderr?.call(chunk);
      }),
    ]);

    if (stdin != null) {
      process.stdin.write(stdin);
      await process.stdin.flush();
    }
    await process.stdin.close();

    final int exitCode = await _awaited(
      process,
      executable: executable,
      timeout: timeout,
      out: out,
      err: err,
      draining: draining,
    );
    await draining;

    return ProcessOutcome(
      exitCode: exitCode,
      stdout: out.join(),
      stderr: err.join(),
    );
  }

  Future<int> _awaited(
    Process process, {
    required String executable,
    required Duration? timeout,
    required List<String> out,
    required List<String> err,
    required Future<void> draining,
  }) async {
    if (timeout == null) {
      return process.exitCode;
    }

    try {
      return await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      await draining
          .timeout(drainGrace, onTimeout: () => const <void>[])
          .catchError((Object _) => const <void>[]);
      throw ProcessTimeout(
        executable: executable,
        limit: timeout,
        stdout: out.join(),
        stderr: err.join(),
      );
    }
  }

  @override
  Future<int> launch(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final Process process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      mode: ProcessStartMode.detached,
    );
    return process.pid;
  }
}
