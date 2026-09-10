/// A aparência que o sistema pede.
///
/// Três valores, e o terceiro é o motivo de isto existir.
///
/// O Flutter expõe `platformBrightness`, que é `light` ou `dark` — não há
/// terceiro. Um sistema que não declarou preferência chega como `light`,
/// exatamente igual a um usuário que escolheu claro, e quem lê não tem como
/// separar os dois. Para um app cujo padrão é escuro, essa é a diferença entre
/// respeitar a escolha do usuário e desobedecer a ela.
enum SystemAppearance {
  /// O sistema não declarou preferência, ou não foi possível perguntar.
  ///
  /// É resposta legítima, não falha: o portal XDG do Linux tem esse valor na
  /// especificação (`no preference`), e no Windows a chave do tema só existe
  /// depois que alguém mexe nele. Também é o que se recebe quando o nativo não
  /// está carregado — num teste de widget, por exemplo.
  unknown,

  /// O sistema pede tema claro.
  light,

  /// O sistema pede tema escuro.
  dark;

  /// O valor que o nativo devolve, traduzido.
  ///
  /// Qualquer inteiro fora da tabela vira [unknown] em vez de lançar: um
  /// nativo mais novo que este Dart pode devolver um valor que ele ainda não
  /// conhece, e derrubar o app por causa de uma cor seria a troca errada.
  static SystemAppearance fromNative(int value) => switch (value) {
    1 => SystemAppearance.light,
    2 => SystemAppearance.dark,
    _ => SystemAppearance.unknown,
  };
}
