/// Por onde um artefato sai, e para quem.
///
/// O `ship` era uma esteira so: build de release, assinatura de verdade,
/// notarizacao quando configurada, e um manifesto de updater no fim. Nao havia
/// como dizer "um build para a equipe testar": isso virava uma sequencia de
/// flags desligadas, e nenhuma delas dizia o que o conjunto significava.
///
/// O canal e essa frase. `release` e o que sempre existiu — o padrao, para nada
/// quebrar. `internal` e o build que entrega para quem testa ANTES de existir
/// um Developer ID: debug, assinatura ad-hoc, o instalador que sabe instalar o
/// componente privilegiado declarado, e nenhum manifesto.
enum ShipChannel {
  /// O canal publicado. Nada muda em relacao ao que o `ship` ja fazia.
  release,

  /// O canal interno, para quem testa antes do Developer ID.
  ///
  /// As quatro coisas que ele significa, todas derivadas da configuracao e
  /// nenhuma especifica de um app:
  ///
  /// 1. build de DEBUG — simbolos e log preservados, nao um release
  ///    descascado, que e o unico jeito de o testador dizer o que falhou;
  /// 2. assinatura AD-HOC no macOS, sem Developer ID e sem notarizacao;
  /// 3. o formato de instalador que consegue instalar o componente
  ///    privilegiado declarado (o `.pkg` no macOS, o `.deb`/`.rpm` no Linux);
  /// 4. NENHUM manifesto de updater: um artefato interno nao pode aparecer no
  ///    canal de atualizacao de quem usa a versao publicada, e o `ship` recusa
  ///    a combinacao em vez de confiar na disciplina de quem roda o comando.
  internal;

  static const List<String> names = <String>['release', 'internal'];

  static ShipChannel parse(String value) => switch (value) {
    'release' => ShipChannel.release,
    'internal' => ShipChannel.internal,
    _ => throw ArgumentError('unknown channel "$value"'),
  };

  bool get isInternal => this == ShipChannel.internal;

  /// O que o canal instala do componente privilegiado, para o `doctor` e para
  /// as recusas do plano falarem a mesma lingua.
  String get wire => name;
}
