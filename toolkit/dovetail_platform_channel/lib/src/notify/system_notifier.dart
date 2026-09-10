import 'package:dovetail_platform_channel/src/notify/system_notice.dart';
import 'package:dovetail_platform_channel/src/permission/notification_permission.dart';

/// Publica avisos no serviço de notificação do sistema.
abstract interface class SystemNotifier {
  /// A permissão de notificar, que é pergunta de tempo de execução.
  ///
  /// Fica aqui, e não em `DesktopPlatform`, porque é a permissão DESTE
  /// notificador: quem troca o notificador por um duplo em teste troca a
  /// permissão junto, e as duas coisas não podem discordar.
  NotificationPermission get permission;

  /// Publica o aviso, ou lança dizendo por que ele não vai aparecer.
  Future<void> show(SystemNotice notice);

  Future<void> cancel(int id);
  Future<void> cancelAll();
}
