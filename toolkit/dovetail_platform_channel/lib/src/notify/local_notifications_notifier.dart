import 'dart:async';
import 'dart:io';

import 'package:dovetail_platform_channel/src/notify/notifications_unavailable.dart';
import 'package:dovetail_platform_channel/src/notify/session_bus.dart';
import 'package:dovetail_platform_channel/src/notify/system_notice.dart';
import 'package:dovetail_platform_channel/src/notify/system_notifier.dart';
import 'package:dovetail_platform_channel/src/permission/notification_permission.dart';
import 'package:dovetail_platform_channel/src/permission/notification_permission_refused.dart';
import 'package:dovetail_platform_channel/src/permission/permission_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// As notificações do sistema, pelo `flutter_local_notifications`.
///
/// Duas coisas aqui não são repasse, e são as duas que já custaram caro:
/// [attach] não pede permissão a ninguém, e [show] recusa em voz alta em vez
/// de sumir com o aviso. Os comentários de cada uma dizem o que quebrou.
final class LocalNotificationsNotifier implements SystemNotifier {
  LocalNotificationsNotifier({
    required this.applicationId,
    required this.displayName,
    required this.guid,
    FlutterLocalNotificationsPlugin? plugin,
    SessionBus? bus,
    NotificationPermission? permission,
    TargetPlatform? platform,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _platform = platform ?? defaultTargetPlatform,
       _bus =
           bus ??
           SessionBus(
             environment: Platform.environment,
             onLinux: Platform.isLinux,
           ) {
    _permission =
        permission ??
        SystemNotificationPermission(
          applicationId: applicationId,
          platform: _platform,
        );
  }

  final String applicationId;
  final String displayName;
  final String guid;

  final FlutterLocalNotificationsPlugin _plugin;
  final SessionBus _bus;
  final TargetPlatform _platform;
  late final NotificationPermission _permission;

  bool _initialized = false;
  String? _unavailableBecause;

  /// Se o serviço de notificação foi alcançado e aceitou registrar o app.
  ///
  /// Não diz nada sobre permissão: um app pode estar disponível e negado ao
  /// mesmo tempo, e é [permission] que responde a segunda pergunta.
  bool get isAvailable => _initialized;

  String? get unavailableBecause => _unavailableBecause;

  /// A permissão de notificar deste app, para ler, pedir e abrir o painel.
  @override
  NotificationPermission get permission => _permission;

  /// Registra o app no serviço de notificação da sessão.
  ///
  /// NÃO pede permissão, e é preciso dizer isso porque o padrão do plugin é o
  /// contrário: `DarwinInitializationSettings` liga os três pedidos sozinho, e
  /// o diálogo do macOS aparecia no boot, antes de a pessoa ter qualquer ideia
  /// do que o app quer notificar. Um "não" ali é definitivo — o sistema não
  /// mostra o diálogo de novo —, então o custo de perguntar cedo demais é
  /// perder a permissão para sempre. Quem quiser o diálogo chama
  /// `permission.request()` num momento que se explique.
  Future<bool> attach() async {
    if (_initialized) {
      return true;
    }
    if (!_bus.reachable) {
      _unavailableBecause = _bus.absentBecause;
      return false;
    }

    final Completer<void> settled = Completer<void>();
    runZonedGuarded(() async {
      try {
        final bool? answer = await _plugin.initialize(settings: _settings);
        if (_startedFrom(answer)) {
          _initialized = true;
          _unavailableBecause = null;
        } else {
          _unavailableBecause = _refusalFrom(answer);
        }
      } on Object catch (error) {
        _unavailableBecause = '$error';
      }
      if (!settled.isCompleted) {
        settled.complete();
      }
    }, _swallow);
    await settled.future;
    return _initialized;
  }

  /// O booleano de `initialize`, que quer dizer coisas diferentes por
  /// plataforma.
  ///
  /// No macOS ele NÃO é "inicializou": é o veredito da autorização que o
  /// `initialize` do plugin pede. Com os três pedidos desligados o plugin
  /// responde `false` sem falar com ninguém — está literalmente escrito assim
  /// no `requestPermissionsImpl` dele — e ler isso como falha deixaria todo
  /// app de macOS sem notificação, que é o oposto do que esta versão quis.
  /// Quem responde a pergunta de permissão no macOS é [permission].
  ///
  /// No Windows o mesmo booleano é o retorno do `init` nativo, e `false` ali é
  /// falha de verdade. No Linux é sempre `true`. `null` é o plugin sem
  /// implementação registrada para esta plataforma.
  bool _startedFrom(bool? answer) {
    if (_platform == TargetPlatform.macOS) {
      return true;
    }
    return answer ?? false;
  }

  String _refusalFrom(bool? answer) => answer == null
      ? 'the notification plugin has no implementation registered for '
            '${_platform.name}, so initialize answered nothing at all'
      : 'the notification service refused to initialise on this session, and '
            'said so by answering false';

  /// Os três pedidos de permissão desligados, e o motivo está em [attach].
  InitializationSettings get _settings => InitializationSettings(
    macOS: const DarwinInitializationSettings(
      requestAlertPermission: false,
      requestSoundPermission: false,
      requestBadgePermission: false,
    ),
    linux: LinuxInitializationSettings(defaultActionName: displayName),
    windows: WindowsInitializationSettings(
      appName: displayName,
      appUserModelId: applicationId,
      guid: guid,
    ),
  );

  void _swallow(Object error, StackTrace trace) {
    _unavailableBecause ??= '$error';
    stderr.writeln(
      'the notification service failed after it was reached, and the app is '
      'carrying on without notifications: $error',
    );
  }

  /// Publica o aviso, ou recusa dizendo por quê.
  ///
  /// A leitura da permissão é feita AGORA, a cada aviso, e não guardada de
  /// [attach]: a pessoa pode desligar a notificação do app nos Ajustes com ele
  /// aberto, e um valor guardado no boot continuaria dizendo que está tudo
  /// certo enquanto nada mais aparece. É uma ida ao sistema por notificação,
  /// que é barata perto de uma notificação que some.
  @override
  Future<void> show(SystemNotice notice) async {
    _refuseIfUnavailable();
    await _refuseIfNotPermitted();
    await _plugin.show(id: notice.id, title: notice.title, body: notice.body);
  }

  @override
  Future<void> cancel(int id) async {
    _refuseIfUnavailable();
    await _plugin.cancel(id: id);
  }

  @override
  Future<void> cancelAll() async {
    _refuseIfUnavailable();
    await _plugin.cancelAll();
  }

  void _refuseIfUnavailable() {
    if (_initialized) {
      return;
    }
    throw NotificationsUnavailable(
      _unavailableBecause ?? 'attach has not been called',
    );
  }

  /// Cancelar não passa por aqui de propósito: retirar um aviso que já está na
  /// tela continua valendo mesmo depois de a permissão ser revogada.
  Future<void> _refuseIfNotPermitted() async {
    final PermissionState state = await _permission.state();
    if (state.mayDeliver) {
      return;
    }
    throw NotificationPermissionRefused(state);
  }
}
