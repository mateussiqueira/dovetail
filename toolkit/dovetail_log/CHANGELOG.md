# Changelog

## 0.1.0 — unreleased

- `AppLog` writes stamped lines to one file and rotates it at `maxBytes`,
  keeping `keep` older files; `attach` adds a stream of lines from Rust.
