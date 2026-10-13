import 'dart:convert';
import 'dart:typed_data';

import 'package:dovetail_store/src/atomic_file.dart';

final class KeyValueStore {
  KeyValueStore._(this._file, this._entries);

  factory KeyValueStore.open(String path) {
    final AtomicFile file = AtomicFile(path);
    final Uint8List? bytes = file.read();
    if (bytes == null) {
      return KeyValueStore._(file, <String, Object?>{});
    }
    final Object? decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?>) {
      throw FormatException('the store is not a JSON object', path);
    }
    return KeyValueStore._(file, decoded);
  }

  final AtomicFile _file;
  Map<String, Object?> _entries;

  Iterable<String> get keys => _entries.keys;

  bool containsKey(String key) => _entries.containsKey(key);

  Object? get(String key) => _entries[key];

  void set(String key, Object? value) =>
      _save(<String, Object?>{..._entries, key: value});

  void remove(String key) {
    if (_entries.containsKey(key)) {
      _save(<String, Object?>{..._entries}..remove(key));
    }
  }

  void _save(Map<String, Object?> next) {
    _file.write(_encoded(next));
    _entries = next;
  }

  static Iterable<List<int>> _encoded(Map<String, Object?> entries) sync* {
    String separator = '{';
    for (final MapEntry<String, Object?> entry in entries.entries) {
      final String value = jsonEncode(entry.value);
      yield utf8.encode('$separator${jsonEncode(entry.key)}:$value');
      separator = ',';
    }
    yield utf8.encode(separator == '{' ? '{}' : '}');
  }
}
