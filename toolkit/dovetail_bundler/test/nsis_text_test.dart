import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:test/test.dart';

void main() {
  test('escape should protect the dollar sign NSIS treats as special', () {
    expect(NsisText.escape(r'C:\Cost$5'), r'C:\Cost$$5');
  });

  test('escape should protect a quote so the script keeps parsing', () {
    expect(NsisText.escape('say "hi"'), r'say $\"hi$\"');
  });

  test('escape should protect the backtick', () {
    expect(NsisText.escape('a`b'), r'a$\`b');
  });

  test('escape should turn newlines and tabs into NSIS sequences', () {
    expect(NsisText.escape('a\nb'), r'a$\nb');
    expect(NsisText.escape('a\r\nb'), r'a$\r$\nb');
    expect(NsisText.escape('a\tb'), r'a$\tb');
  });

  test('define should quote and escape the value', () {
    expect(
      NsisText.define('PRODUCTNAME', r'My "App" $x'),
      r'!define PRODUCTNAME "My $\"App$\" $$x"',
    );
  });

  test('escape should leave a plain windows path alone', () {
    expect(
      NsisText.escape(r'C:\Program Files\Example'),
      r'C:\Program Files\Example',
    );
  });
}
