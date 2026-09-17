/// Por onde o componente privilegiado chega à máquina no macOS.
///
/// As duas rotas existem em produtos reais e não são intercambiáveis: uma é
/// decisão de empacotamento, e a outra é decisão de quem instala.
enum DarwinServiceRoute {
  /// O daemon viaja DENTRO do bundle, em `Contents/Library/LaunchDaemons`, e o
  /// próprio aplicativo o registra em runtime com `SMAppService`.
  ///
  /// É a única rota que funciona a partir do `.dmg` que este projeto empacota,
  /// e a que a Apple documenta desde o macOS 13. O usuário vê um interruptor em
  /// Ajustes do Sistema, não um pedido de senha; desinstalar o aplicativo leva
  /// o daemon junto, sem resíduo em `/Library`.
  ///
  /// Custo: `SMAppService` exige assinatura válida e o MESMO Team ID no
  /// aplicativo e no daemon. Um build assinado ad-hoc — o padrão do debug — é
  /// recusado no registro.
  bundled,

  /// O daemon é instalado em `/Library/LaunchDaemons` por um instalador que já
  /// roda como root — um `.pkg`, ou um operador com `sudo`.
  ///
  /// Funciona sem Developer ID e serve a máquina inteira, mas exige um formato
  /// de pacote que este projeto não produz hoje. Declará-la é dizer que a
  /// instalação acontece fora do `.dmg`.
  system,
}
