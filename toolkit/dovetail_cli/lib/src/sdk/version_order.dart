/// A mais nova entre [a] e [b], por segmento numérico — o sort de string
/// põe `0.10.0` antes de `0.9.0` e a "mais recente" sairia errada.
///
/// É o comparador do locator (qual SDK instalado usar) e do `self-update`
/// (se o `latest` do canal é de fato mais novo que o binário) — uma regra,
/// dois consumidores, para as duas pontas nunca discordarem.
String newerVersion(String a, String b) {
  final List<String> as = a.split('.');
  final List<String> bs = b.split('.');
  final int length = as.length > bs.length ? as.length : bs.length;
  for (int i = 0; i < length; i++) {
    final int ai = i < as.length ? int.tryParse(as[i]) ?? 0 : 0;
    final int bi = i < bs.length ? int.tryParse(bs[i]) ?? 0 : 0;
    if (ai != bi) {
      return ai > bi ? a : b;
    }
  }
  return a;
}
