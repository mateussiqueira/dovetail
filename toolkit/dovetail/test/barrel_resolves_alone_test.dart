// Importa SO o barril. Nada mais.
//
// Este arquivo e um consumidor de mentira com a unica dependencia que um
// consumidor de verdade tem: `package:dovetail/dovetail.dart`. Cada tipo que a
// API publica nomeia numa assinatura e escrito aqui uma vez, entao um tipo que
// o barril deixa de reexportar — como `Version`, do pub_semver, que a API do
// updater expoe e ninguem reexportava — deixa de COMPILAR neste arquivo em vez
// de no projeto de quem consome. O teste em si e trivial; o que prova e o
// import resolver.
import 'package:dovetail/dovetail.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every type the public API names resolves through the barrel', () {
    // updater: a API fala Version (pub_semver) — tinha que vir pelo barril.
    final Version version = Version.parse('1.2.3');
    expect(version.major, 1);

    // canal: o TIPO e DisplayProbe; a implementacao nao e publica.
    const DisplayProbe? probe = null;
    expect(probe, isNull);

    // o resto da superficie, um por pacote, para o import nao ficar so nos
    // dois acima.
    expect(SingleInstanceVerdict.values, isNotEmpty);
    expect(ShortcutBackend.values, isNotEmpty);
    expect(UpdateOs.values, isNotEmpty);
    expect(const RequiredField('x'), isA<FieldValidation>());
    expect(const SystemProcessRunner(), isA<ProcessRunner>());
  });
}
