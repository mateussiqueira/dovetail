import 'package:dovetail_bundler/src/xml_text.dart';

abstract final class WixText {
  static const int identifierLimit = 72;

  /// The name stays, and delegates: seventeen call sites say what they mean
  /// with these two, and what they mean is WiX source text — the escape
  /// itself is [XmlText]'s, shared with the polkit policy and the daemon
  /// plist, which were the reason not to write a third copy here.
  static String attribute(String value) => XmlText.attribute(value);

  static String content(String value) => XmlText.content(value);

  static String identifier(String value, {String prefix = 'id'}) {
    final StringBuffer buffer = StringBuffer();
    for (final int unit in value.codeUnits) {
      buffer.writeCharCode(_isIdentifierSafe(unit) ? unit : 0x5F);
    }
    final String sanitized = buffer.toString();
    final String seeded = _startsIdentifier(sanitized)
        ? sanitized
        : '$prefix$sanitized';
    return seeded.length <= identifierLimit
        ? seeded
        : '${seeded.substring(0, identifierLimit - 9)}_${_fold(value)}';
  }

  static bool _isIdentifierSafe(int unit) =>
      (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x5A) ||
      (unit >= 0x61 && unit <= 0x7A) ||
      unit == 0x5F ||
      unit == 0x2E;

  static bool _startsIdentifier(String value) {
    if (value.isEmpty) {
      return false;
    }
    final int unit = value.codeUnitAt(0);
    return (unit >= 0x41 && unit <= 0x5A) ||
        (unit >= 0x61 && unit <= 0x7A) ||
        unit == 0x5F;
  }

  static String _fold(String value) {
    int hash = 0x811C9DC5;
    for (final int unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0').toUpperCase();
  }
}
