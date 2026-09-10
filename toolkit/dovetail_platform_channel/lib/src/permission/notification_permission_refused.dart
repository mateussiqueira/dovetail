import 'package:dovetail_platform_channel/src/permission/permission_state.dart';

/// O sistema não vai entregar esta notificação, e alguém precisa saber disso.
///
/// Existe porque a alternativa é o silêncio: `show()` numa permissão negada
/// retorna sem erro, a notificação não aparece, e não há onde ler o porquê —
/// nem no app, nem no log, nem para a pessoa que esperava o aviso. Foi
/// exatamente esse o bug que o `initialize()` deste pacote tinha, engolindo a
/// resposta de concessão.
///
/// A mensagem diz o que fazer em cada estado, porque são caminhos diferentes:
/// pedir, mandar aos Ajustes, ou nada.
final class NotificationPermissionRefused implements Exception {
  const NotificationPermissionRefused(this.state);

  /// O estado que recusou. Nunca [PermissionState.granted] nem
  /// [PermissionState.unsupported] — esses dois entregam.
  final PermissionState state;

  @override
  String toString() => switch (state) {
    PermissionState.notDetermined =>
      'the notification was not shown because nobody has been asked yet. '
          'Initialisation deliberately does not ask — a permission dialog at '
          'boot arrives before the person can know what the app wants it for. '
          'Call NotificationPermission.request() at a moment that explains '
          'itself, and show this notice after it answers.',
    PermissionState.denied =>
      'the notification was not shown because this app was refused permission '
          'to notify. Asking again does nothing: the system does not show the '
          'dialog twice. NotificationPermission.openSettings() is the only '
          'way back.',
    PermissionState.restricted =>
      'the notification was not shown because notifications are blocked by '
          'policy on this machine — an administrator, an MDM profile or '
          'parental controls. It is not the user choice, and the settings '
          'pane will not let them change it.',
    PermissionState.granted || PermissionState.unsupported =>
      'the notification was not shown, and the permission state says it '
          'should have been ($state). This is a bug in dovetail_platform_'
          'channel, not in the app.',
  };
}
