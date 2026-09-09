**English** · [Português](README.pt-BR.md)

# dovetail_process_runner

> Run a process and get back what it said — with a double the tests use in its
> place, and without the three deadlocks `Process.run` ships with.

Half of what this toolkit does is call somebody else's tool: `codesign`,
`signtool`, `minisign`, `hdiutil`, `dpkg`, `rpmbuild`, `makensis`, `wixl`,
`osslsigncode`, `pkexec`. A whole package for that exists for two reasons, and
neither is elegance.

## The reason that shows up in the tests

`ProcessRunner` is an interface. Every bundler, every signer and every
installer receives one through its constructor, so the test passes a double and
**pins the arguments** — not the result of having run the tool, which may not
even be installed on the reader's machine.

```dart
final RecordingRunner runner = RecordingRunner();
await DmgBundler(runner: runner).bundle(spec);

expect(runner.arguments, containsAllInOrder(<String>['-volname', 'Example']));
```

That is why `dovetail_bundler` proves the command line for `wixl` and
`rpmbuild` on a Mac that has neither. Where the tool does exist, the same test
runs with `SystemProcessRunner` and checks the file that came out.

## The reason that does not show up: three deadlocks

**The first is output filling the pipe.** An OS pipe holds about 64 KB. If the
child process writes more than that and nobody reads, it blocks on the write —
and whoever is waiting for `exitCode` waits forever. Here, draining `stdout` and
`stderr` starts **before** anything is written to `stdin`, not after:

```dart
final Future<void> draining = Future.wait(<Future<void>>[...]);   // first
if (stdin != null) { process.stdin.write(stdin); }                 // then
```

Three tests pin that with genuinely large output — on `stdout`, on `stderr`,
and with large `stdin` alongside — because the version that swaps those two
lines passes every small test.

**The second is `stdin` that never closes.** `minisign` waits for a password on
`stdin` and does not finish while the descriptor is open. `close()` is
unconditional, not only when there was something to write.

**The third is the process that hangs.** `timeout` kills with `SIGKILL`, waits
for the real `exitCode`, gives the draining a short grace period, and throws a
`ProcessTimeout` carrying **what the process had said up to that point** —
which is exactly where the clue about why it hung lives.

## What it returns

```dart
final ProcessOutcome outcome = await runner.run('minisign', <String>[
  '-S', '-s', keyPath, artifactPath,
], stdin: '$password\n', timeout: const Duration(seconds: 60));

if (!outcome.succeeded) {
  throw SigningFailure('minisign failed', remedy: outcome.firstDiagnostic);
}
```

`firstDiagnostic` prefers `stderr`, falls back to `stdout` when that is blank,
and when both are empty it states the exit code — instead of returning an empty
string as the reason, which is how a failure becomes "something went wrong".

`toString` reports the **size** of `stdout` and `stderr`, not their contents: a
`ProcessOutcome` in an error log should not dump ten thousand lines nor, worse,
echo what was written to `stdin`.

## `ProcessLauncher` is a different thing, on purpose

```dart
final int pid = await launcher.launch('msiexec', <String>['/i', installer]);
```

`run` waits and captures. `launch` **releases the process and returns the
pid**, detached — which is what the Windows installer needs, because the `.msi`
replaces the executable that is running and the app has to exit before it
finishes. Waiting there would be waiting for a process that only finishes after
killing the waiter.

`SystemProcessRunner` implements both interfaces, and whoever depends on only
one declares only that one.

## What this package does not do

It does not interpret output, does not know any tool, and does not decide what
counts as failure beyond the exit code. `runInShell` is `false` and not
configurable: passing a line through a shell is how a path with a space becomes
two arguments, and how a file name from outside becomes a command.
