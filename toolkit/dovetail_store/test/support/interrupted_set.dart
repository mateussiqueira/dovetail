import 'dart:io';

import 'package:dovetail_store/dovetail_store.dart';

final class _Stalling {
  const _Stalling(this.marker);

  final String marker;

  Object? toJson() {
    File(marker).writeAsStringSync('halfway');
    sleep(const Duration(minutes: 1));
    return null;
  }
}

void main(List<String> arguments) {
  KeyValueStore.open(arguments[0]).set('stalls', _Stalling(arguments[1]));
}
