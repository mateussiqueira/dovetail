/// O que o sistema responde AGORA quando o app pergunta se pode notificar.
///
/// # Por que não é um booleano
///
/// Um booleano junta os dois estados que pedem jornadas opostas. Em
/// [notDetermined] o app PODE perguntar, e o sistema mostra o diálogo. Em
/// [denied] ele nunca mais pode: o macOS não reexibe o diálogo para quem já
/// respondeu, então pedir de novo não faz nada — silenciosamente. Uma tela
/// construída sobre "pode ou não pode" manda a pessoa apertar um botão que
/// deixou de ter efeito, e ninguém descobre por quê. Com os dois estados
/// separados, `denied` leva para o painel do sistema, que é o único caminho
/// de volta.
///
/// [restricted] é separado porque não é escolha da pessoa: é MDM, controle
/// parental, política de organização. Dizer "libere nas configurações" a quem
/// não tem permissão de liberar é pior do que não dizer nada.
///
/// # E [unsupported]
///
/// É a plataforma que não tem esse conceito — Linux não pergunta nada a
/// ninguém — e também este build sem o nativo para perguntar. Nos dois casos
/// a resposta honesta não é "concedido" nem "negado": é que a pergunta não se
/// aplica aqui. Quem chama decide, e [mayDeliver] já responde o caso comum:
/// entregar a notificação é o certo nos dois.
///
/// A ordem importa. Ela é a tabela do ABI em
/// `include/dovetail_platform_channel/dovetail_notification_permission.h`, e
/// o zero é [unsupported] pelo mesmo motivo de `SystemAppearance.unknown`:
/// um valor não inicializado, uma chave ausente e um nativo que não carregou
/// caem todos na resposta que não inventa nada.
enum PermissionState {
  /// Não há permissão a pedir aqui.
  ///
  /// Linux é o caso permanente: o serviço de notificação do desktop atende
  /// quem estiver no barramento, sem diálogo nenhum. O caso temporário é um
  /// app construído antes deste pacote ter o nativo, e um `flutter test`, onde
  /// plugin nenhum está carregado.
  unsupported,

  /// Ninguém foi perguntado ainda, e perguntar é permitido.
  ///
  /// É o único estado em que `NotificationPermission.request()` faz alguma
  /// coisa visível.
  notDetermined,

  /// A pessoa deixou, e o sistema entrega.
  ///
  /// No macOS a autorização provisória cai aqui: ela entrega — em silêncio, na
  /// central — e do ponto de vista de quem publica um aviso isso é entregar.
  granted,

  /// A pessoa recusou, e só o painel do sistema desfaz.
  ///
  /// Pedir de novo daqui não abre diálogo nenhum. `openSettings()` existe para
  /// este estado.
  denied,

  /// Não é a pessoa que decide.
  ///
  /// Quem produz este valor hoje é o Windows sob política de administrador
  /// (`NoToastApplicationNotification`). A `UNAuthorizationStatus` do macOS
  /// não tem equivalente — o que existia morreu com a `NSUserNotification` —,
  /// então lá este estado não aparece.
  restricted;

  /// O inteiro do ABI nativo, traduzido.
  ///
  /// Qualquer valor fora da tabela vira [unsupported] em vez de lançar: um
  /// nativo mais novo que este Dart pode responder um estado que ele ainda não
  /// conhece, e a leitura de uma permissão não é lugar de derrubar o app.
  static PermissionState fromNative(int value) => switch (value) {
    1 => PermissionState.notDetermined,
    2 => PermissionState.granted,
    3 => PermissionState.denied,
    4 => PermissionState.restricted,
    _ => PermissionState.unsupported,
  };

  /// Se ainda faz sentido mostrar o diálogo do sistema.
  bool get mayAsk => this == PermissionState.notDetermined;

  /// Se uma notificação publicada agora tem chance de aparecer.
  ///
  /// [unsupported] entra aqui de propósito: é o Linux, e é o app sem o nativo.
  /// Recusar a entrega nesses dois casos apagaria notificações que funcionam.
  bool get mayDeliver =>
      this == PermissionState.granted || this == PermissionState.unsupported;

  /// Se mandar a pessoa ao painel do sistema resolve.
  ///
  /// Só [denied]. Em [restricted] o painel está lá e a chave está travada por
  /// quem administra a máquina, e mandar alguém até lá para não poder fazer
  /// nada é a pior das telas possíveis.
  bool get settingsCanRecoverIt => this == PermissionState.denied;
}
