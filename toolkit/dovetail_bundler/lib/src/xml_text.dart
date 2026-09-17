/// The XML the format generators emit: the `.wxs` and its WiX fragment on
/// Windows, the polkit policy on Linux, the LaunchDaemon property list on
/// macOS.
///
/// The escape existed twice — [WixText.attribute]/[WixText.content] and a
/// private `_escape` inside [PolkitPolicy] — before the property list became
/// the third generator, and a third copy was the moment to lift it. The
/// platform folders keep what they always separated, the packaging formats;
/// the escape is none of the three formats, it is the XML underneath them.
///
/// The two names keep the distinction the two copies already made: text
/// inside an element cannot carry `&`, `<` or `>` raw, and text inside a
/// quoted attribute also cannot carry the quotes that would close it. `&`
/// goes first, or the second pass would re-escape the entities the first
/// pass wrote.
abstract final class XmlText {
  /// Text that goes inside an element.
  static String content(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  /// Text that goes inside a double-quoted attribute.
  static String attribute(String value) =>
      content(value).replaceAll('"', '&quot;').replaceAll("'", '&apos;');
}
