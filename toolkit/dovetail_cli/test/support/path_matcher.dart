import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Matcher pathEqualTo(String expected) => predicate<String>(
  (String actual) => p.equals(actual, expected),
  'same filesystem path as $expected',
);
