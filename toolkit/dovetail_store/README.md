# dovetail_store

> A write that a dying process cannot leave half done.

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
