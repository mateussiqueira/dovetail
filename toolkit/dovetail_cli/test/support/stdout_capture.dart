import 'dart:io';

/// A [Stdout] that records what is written to it, so a test can assert on a
/// command's output without letting it reach the terminal.
///
/// [Stdout] is a concrete class with a private constructor, so the only way
/// to stand in for it is `implements` + `noSuchMethod`; the commands write
/// through `writeln`/`write`, and those are the only invocations recorded.
final class CapturedStdout implements Stdout {
  final StringBuffer text = StringBuffer();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #writeln || invocation.memberName == #write) {
      final Object? first = invocation.positionalArguments.isEmpty
          ? null
          : invocation.positionalArguments.first;
      if (first != null) {
        text.write(first);
      }
      if (invocation.memberName == #writeln) {
        text.write('\n');
      }
    }
    return null;
  }
}

/// Runs [body] with `stdout` redirected into [captured], returning whatever
/// [body] returns. The zone is preserved across awaits, so output from the
/// command's own asynchronous flow is captured too.
T capturingStdout<T>(CapturedStdout captured, T Function() body) =>
    IOOverrides.runZoned<T>(body, stdout: () => captured);
