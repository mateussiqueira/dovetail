# Changelog

## 0.1.0 — unreleased

- `AtomicFile` replaces a file through a temporary file, `fsync`, `rename`
  and a synced directory, so a process that dies in the middle of a write
  leaves the old content whole.
- `KeyValueStore` keeps a JSON object on disk, written through `AtomicFile`
  on every `set` and `remove`; a child process killed with `SIGKILL` in the
  middle of a `set` leaves the store whole.
