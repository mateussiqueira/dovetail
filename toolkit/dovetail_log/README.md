# dovetail_log

> One log file for the app, rotated at a size cap, with the Rust core's lines
> in it.

`AppLog` appends `<UTC timestamp> LEVEL target: message` lines to one file.
When a line would push the file past `maxBytes`, `app.log` becomes
`app.log.1`, `app.log.1` becomes `app.log.2`, and so on up to `keep`.

```dart
final AppLog log = AppLog(path: '$supportDirectory/logs/app.log');
log.info('window restored');
log.attach(rustLines);
```

`attach` writes a `Stream<String>` of preformatted lines into the same file:
the `log_lines()` stream of `dovetail_rust_core`, pumped to Dart by a bridge.

Measured on macOS arm64; not run on Windows or Linux.
