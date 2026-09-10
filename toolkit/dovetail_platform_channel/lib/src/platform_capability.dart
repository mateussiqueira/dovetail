/// O que uma plataforma sabe fazer, decidido pela plataforma e mais nada.
///
/// Toda resposta aqui vale para a vida inteira do processo: o Linux não ganha
/// tooltip de bandeja no meio da execução. Por isso `PlatformCapabilities`
/// responde a partir de `defaultTargetPlatform`, sem perguntar ao sistema.
///
/// # Por que não há uma capacidade de permissão
///
/// A tentação é acrescentar `notificationPermission` a esta lista, e seria uma
/// armadilha. Permissão não é estática — ela muda enquanto o app está aberto,
/// por uma decisão tomada fora dele — e duplicá-la aqui criaria duas fontes
/// para a mesma pergunta, que uma hora discordam: a lista diria "esta
/// plataforma pede permissão" enquanto `NotificationPermission.state()` já
/// respondeu `unsupported` porque o nativo não carregou. Uma tela construída
/// sobre a lista ofereceria um botão que a outra fonte sabe que não faz nada.
///
/// Quem responde "há permissão a pedir aqui?" é `PermissionState.unsupported`,
/// vindo do mesmo objeto que responde qual é o estado.
enum PlatformCapability {
  framelessWindow,
  windowPreventClose,
  skipTaskbar,
  trayIcon,
  trayTooltip,
  trayMenu,
  anchoredPanel,
  launchAtLogin,
  singleInstance,
  deepLink,

  /// A plataforma tem serviço de notificação.
  ///
  /// Não diz que este app pode notificar — isso é `NotificationPermission`. As
  /// duas coisas são verdadeiras ao mesmo tempo num macOS onde a pessoa
  /// recusou o diálogo.
  notification,

  externalOpen,
}
