# Changelog

## 0.1.0 — unreleased

- `AtomicFile` replaces a file through a temporary file, `fsync`, `rename`
  and a synced directory, so a process that dies in the middle of a write
  leaves the old content whole.
