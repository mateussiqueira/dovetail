# dovetail_relaunch

> Start the app again, the way the user would, once the running copy is gone.

`RelaunchCommand.forHost` assembles the command that brings the app back after
it exits, which is what an updater needs once it has swapped the app:

- **macOS**: `open -n` on the `.app` bundle, not on the binary inside it, so
  LaunchServices owns the new process. A binary outside a bundle is started
  directly.
- **Linux**: inside an AppImage, the path in `APPIMAGE`, because the binary
  lives in a mount that goes away with the old process; otherwise the binary.
- **Windows**: the same executable, through `powershell.exe` and an
  `-EncodedCommand` script, so no quoting rule of the PowerShell command line
  applies. Each argument is quoted the way the Windows C runtime splits a
  command line.

The command waits until the old pid is gone, with `/bin/sh` or with
`Wait-Process`, and only then starts the new process. An app with a
single-instance guard would otherwise see the old copy still alive, hand it the
launch and quit.

```dart
final RelaunchCommand command = RelaunchCommand.forHost(
  operatingSystem: Platform.operatingSystem,
  executable: Platform.resolvedExecutable,
  pid: pid,
  environment: Platform.environment,
);
```

Measured on macOS arm64, where the waiting script runs against a real process.
Linux runs the same POSIX `sh` and was not run; Windows was written and not
run.
