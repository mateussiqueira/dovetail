import 'dart:io';

import 'package:dovetail_platform_channel/src/notify/session_bus.dart';
import 'package:dovetail_platform_channel/src/open/external_opener.dart';
import 'package:dovetail_platform_channel/src/open/url_launcher_opener.dart';
import 'package:dovetail_platform_channel/src/permission/permission_state.dart';
import 'package:dovetail_platform_channel/src/permission/windows_notification_setting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A permissão de notificar: o que o sistema responde hoje, o pedido, e o
/// caminho de volta quando o pedido não é mais possível.
///
/// # Por que não é uma capacidade
///
/// `PlatformCapability` responde "esta plataforma sabe fazer isto", e a
/// resposta é a mesma na vida inteira do app. Permissão é o oposto: ela muda
/// enquanto o app está aberto, por uma decisão tomada FORA dele, e pode ser
/// revogada depois de concedida. As duas perguntas parecem a mesma até a
/// primeira vez em que alguém desliga a notificação nos Ajustes e o app
/// continua achando que pode notificar.
///
/// # As três operações, e por que [openSettings] não é opcional
///
/// Sem ela, [PermissionState.denied] é um beco sem saída: o sistema não
/// reexibe o diálogo para quem já recusou, então [request] deixa de fazer
/// efeito e a única saída é o painel do sistema. Uma UI que só tivesse
/// [request] mostraria um botão que não faz nada.
abstract interface class NotificationPermission {
  /// O que o sistema responde agora, sem perguntar nada a ninguém.
  ///
  /// Nunca abre diálogo. Pode ser chamado a cada retomada de foco da janela,
  /// que é justamente para o que serve `WindowSurface.focusGains()`.
  Future<PermissionState> state();

  /// Pede a permissão, e responde o estado que ficou.
  ///
  /// Só [PermissionState.notDetermined] mostra alguma coisa à pessoa. Nos
  /// outros estados isto é a mesma leitura de [state] — inclusive em
  /// [PermissionState.denied], onde o sistema simplesmente ignora o pedido.
  Future<PermissionState> request();

  /// Abre o painel do sistema onde a permissão pode ser mudada.
  ///
  /// `false` quando não há painel para abrir, e não quando falhou por acaso:
  /// quem chama precisa saber se pode oferecer o botão.
  Future<bool> openSettings();
}

/// A permissão deste sistema, com um caminho por plataforma.
///
/// | | estado | pedido | painel |
/// |---|---|---|---|
/// | macOS | `UNUserNotificationCenter`, por canal de método | abre o diálogo | `x-apple.systempreferences:` |
/// | Windows | chave de registro do AppUserModelId | não há diálogo; relê | `ms-settings:notifications` |
/// | Linux | o barramento de sessão responde ou não | não há diálogo; relê | não há alvo |
///
/// Nas plataformas que não são desktop tudo responde
/// [PermissionState.unsupported] e `false`, como o resto deste pacote.
final class SystemNotificationPermission implements NotificationPermission {
  /// A permissão do app cujo identificador é [applicationId].
  ///
  /// [applicationId] é o AppUserModelId no Windows, que é a chave sob a qual o
  /// sistema guarda o desligamento. As outras duas plataformas o ignoram: no
  /// macOS quem identifica o app é o bundle, e o Linux não guarda nada.
  SystemNotificationPermission({
    required this.applicationId,
    TargetPlatform? platform,
    this.opener = const UrlLauncherOpener(),
    MethodChannel? channel,
    SessionBus? bus,
    WindowsNotificationSetting? windows,
  }) : platform = platform ?? defaultTargetPlatform,
       _channel = channel ?? const MethodChannel(channelName),
       _bus =
           bus ??
           SessionBus(
             environment: Platform.environment,
             onLinux: Platform.isLinux,
           ),
       _windows = windows ?? WindowsNotificationSetting();

  /// O nome do canal do lado macOS, público porque nome de canal é contrato.
  ///
  /// O outro lado está em `macos/Classes/DovetailPlatformChannelPlugin.m`, e
  /// os dois métodos são `state` e `request`.
  static const String channelName = 'dovetail/notification_permission';

  /// O AppUserModelId, que é o que o Windows usa como chave.
  final String applicationId;

  /// A plataforma cujo caminho será seguido.
  final TargetPlatform platform;

  /// Quem entrega a URL do painel ao sistema.
  final ExternalOpener opener;
  final MethodChannel _channel;
  final SessionBus _bus;
  final WindowsNotificationSetting _windows;

  @override
  Future<PermissionState> state() async => switch (platform) {
    TargetPlatform.macOS => await _askMacOS('state'),
    TargetPlatform.windows => _windows.read(applicationId),
    TargetPlatform.linux => _linux(),
    _ => PermissionState.unsupported,
  };

  /// No macOS abre o diálogo; nas outras duas é a mesma leitura de [state].
  ///
  /// Windows e Linux não têm o que pedir — o primeiro entrega até alguém
  /// desligar, o segundo entrega enquanto houver barramento. Fingir um pedido
  /// ali daria a quem chama a impressão de que a pessoa foi consultada.
  @override
  Future<PermissionState> request() async => switch (platform) {
    TargetPlatform.macOS => await _askMacOS('request'),
    _ => await state(),
  };

  /// O painel de cada sistema, e o Linux que não tem um.
  ///
  /// No Linux a recusa é honesta: GNOME, KDE, XFCE e Cinnamon expõem
  /// notificação em painéis diferentes, com identificadores diferentes, e não
  /// há esquema de URL que sirva para todos. Abrir o painel errado — ou o
  /// gerenciador de arquivos, que é o que um `xdg-open` de URI desconhecido
  /// costuma fazer — é pior do que não oferecer o botão. Também não há o que
  /// abrir: o Linux não guarda permissão de notificação em lugar nenhum.
  @override
  Future<bool> openSettings() async {
    final Uri? pane = switch (platform) {
      TargetPlatform.macOS => Uri.parse(
        'x-apple.systempreferences:com.apple.preference.notifications',
      ),
      TargetPlatform.windows => Uri.parse('ms-settings:notifications'),
      _ => null,
    };
    if (pane == null) {
      return false;
    }
    return opener.openUrl(pane);
  }

  /// A ida ao nativo do macOS, com o plugin ausente como resposta legítima.
  ///
  /// [MissingPluginException] aqui é o app construído antes deste canal
  /// existir, e é todo `flutter test`, onde nenhum plugin está registrado.
  /// [PermissionState.unsupported] em vez de propagar porque uma leitura de
  /// permissão que lança obriga toda tela a embrulhar a chamada num try, e a
  /// primeira que esquecer quebra na máquina de quem instalou.
  Future<PermissionState> _askMacOS(String method) async {
    try {
      final int? answer = await _channel.invokeMethod<int>(method);
      return answer == null
          ? PermissionState.unsupported
          : PermissionState.fromNative(answer);
    } on MissingPluginException {
      return PermissionState.unsupported;
    }
  }

  /// O Linux não tem modelo de permissão: tem barramento ou não tem.
  ///
  /// Ninguém pergunta nada ao usuário — o serviço de notificação do desktop
  /// atende quem chegar pelo D-Bus. Barramento alcançável vira
  /// [PermissionState.granted]; sem barramento a resposta é
  /// [PermissionState.unsupported], que não é recusa: é uma sessão sem serviço
  /// nenhum a que pedir, e mandá-la a um painel de Ajustes não resolveria
  /// nada. É a mesma sonda que `LocalNotificationsNotifier` usa para decidir
  /// se sequer inicializa.
  PermissionState _linux() =>
      _bus.reachable ? PermissionState.granted : PermissionState.unsupported;
}
