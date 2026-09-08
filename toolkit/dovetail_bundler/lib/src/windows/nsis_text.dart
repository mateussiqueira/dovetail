abstract final class NsisText {
  static String escape(String value) => value
      .replaceAll(r'$', r'$$')
      .replaceAll('"', r'$\"')
      .replaceAll('`', r'$\`')
      .replaceAll('\r\n', r'$\r$\n')
      .replaceAll('\n', r'$\n')
      .replaceAll('\r', r'$\r')
      .replaceAll('\t', r'$\t');

  static String define(String name, String value) =>
      '!define $name "${escape(value)}"';
}
