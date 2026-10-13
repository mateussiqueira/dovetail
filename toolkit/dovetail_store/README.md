# dovetail_store

> A key-value store for desktop apps, and a write that a dying process cannot
> leave half done.

## The store

`KeyValueStore` keeps a JSON object in one file and writes it through
`AtomicFile` on every `set` and `remove`. The map in memory changes only after
the write succeeds, so a value JSON cannot carry leaves both as they were.

```dart
final KeyValueStore store = KeyValueStore.open('$supportDirectory/prefs.json');
store.set('theme', 'dark');
final Object? theme = store.get('theme');
```

A file that is not a JSON object is refused with a `FormatException`, instead
of being read as empty and overwritten by the next `set`.

The proof is a real process: a child opens the store, starts a `set` whose
value blocks in `toJson` once the first entries are written, and is killed
with `SIGKILL`. The store reopens with its old content.

## The write

`AtomicFile` replaces the content of a file without a moment in which the file
on disk is neither the old version nor the new one:

1. every chunk goes to `<path>.tmp`;
2. the temporary file is flushed to the disk with `fsync`;
3. it is renamed over `<path>`;
4. the directory is flushed too, so the rename itself reaches the disk.

A write that throws halfway deletes its temporary file and leaves the old
content where it was. A temporary file left by a writer that died is simply
overwritten by the next write.

```dart
const AtomicFile file = AtomicFile('/path/to/settings.json');
file.write(<List<int>>[utf8.encode('{"theme":"dark"}')]);
final Uint8List? saved = file.read();
```

Dart cannot open a directory, so step 4 calls `open`, `fsync` and `close` from
the C library through `dart:ffi`. Windows skips it: NTFS has no directory
`fsync`.

Measured on macOS arm64. Linux makes the same POSIX calls and was not run;
Windows was written and not run.
