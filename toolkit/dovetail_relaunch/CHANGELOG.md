# Changelog

## 0.1.0 — unreleased

- `RelaunchCommand.forHost` assembles the relaunch on macOS (the `.app`
  through `open -n`) and Linux (the `APPIMAGE`, or the binary), behind a
  `/bin/sh` that waits for the old pid to exit.
- On Windows, `powershell.exe -EncodedCommand` waits for the old pid with
  `Wait-Process` and starts the same executable with `Start-Process`.
