import 'dart:ffi';
import 'dart:io';

import 'package:dovetail_platform_channel/src/permission/permission_state.dart';
import 'package:ffi/ffi.dart';

typedef _PermissionNative = Int32 Function(Pointer<Utf16>);
typedef _PermissionDart = int Function(Pointer<Utf16>);

const String _symbol = 'DovetailNotificationPermissionFor';

/// O que o registro do Windows diz sobre os toasts de um app.
///
/// # Por que FFI aqui e canal de método no macOS
///
/// A leitura é síncrona e devolve um inteiro, porque no Windows não há
/// diálogo de permissão a esperar: o usuário desliga o app na página de
/// notificações dos Ajustes, e isso vira uma chave de registro. Um canal de
/// método para isso seria serialização e fila de mensagens para ler um
/// número. No macOS a autorização é um bloco de conclusão que responde quando
/// a pessoa clicar, e aí a função C não serve.
///
/// Espelha `SystemAppearanceProbe` de propósito, inclusive na resolução do
/// símbolo no construtor: é o que faz [isAvailable] dizer a verdade num host
/// onde a biblioteca abre e o símbolo não existe — o app construído antes
/// desta versão do pacote.
final class WindowsNotificationSetting {
  /// A leitura deste host, se houver nativo com o símbolo.
  factory WindowsNotificationSetting({DynamicLibrary? library}) {
    final DynamicLibrary? opened = library ?? _open();
    if (opened == null) {
      return const WindowsNotificationSetting.absent();
    }
    try {
      return WindowsNotificationSetting._(
        opened.lookupFunction<_PermissionNative, _PermissionDart>(_symbol),
      );
    } on ArgumentError {
      return const WindowsNotificationSetting.absent();
    }
  }

  const WindowsNotificationSetting._(this._ask);

  /// Uma leitura que não tem a quem perguntar.
  ///
  /// Para teste, e para todo host que não é Windows. [read] devolve
  /// [PermissionState.unsupported], que entrega a notificação em vez de
  /// escondê-la: um app construído antes deste símbolo existir notificava, e
  /// nada nesta versão tira essa permissão dele.
  const WindowsNotificationSetting.absent() : _ask = null;

  final _PermissionDart? _ask;

  /// Se há nativo para perguntar.
  bool get isAvailable => _ask != null;

  /// O estado que o registro descreve para este AppUserModelId.
  ///
  /// Nunca lança, e a memória do argumento é liberada mesmo se o nativo
  /// lançar: um `finally` a mais custa nada e um vazamento por notificação
  /// custa o dia inteiro de quem deixa o app aberto.
  PermissionState read(String appUserModelId) {
    final _PermissionDart? ask = _ask;
    if (ask == null) {
      return PermissionState.unsupported;
    }
    final Pointer<Utf16> argument = appUserModelId.toNativeUtf16();
    try {
      return PermissionState.fromNative(ask(argument));
    } finally {
      malloc.free(argument);
    }
  }

  /// A DLL do plugin, ao lado do executável.
  ///
  /// Um só arquivo com os dois símbolos — a aparência e este —, e por isso o
  /// mesmo nome que `SystemAppearanceProbe` abre.
  static DynamicLibrary? _open() {
    if (!Platform.isWindows) {
      return null;
    }
    try {
      return DynamicLibrary.open('dovetail_platform_channel.dll');
    } on Object {
      return null;
    }
  }
}
