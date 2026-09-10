import 'dart:ui';

import 'package:dovetail_platform_channel/src/window/window_frame_state.dart';

abstract interface class WindowSurface {
  Future<void> show();
  Future<void> hide();
  Future<void> focus();
  Future<void> minimize();
  Future<void> restore();
  Future<void> maximize();
  Future<void> unmaximize();
  Future<bool> isMaximized();
  Future<bool> isVisible();
  Future<WindowFrameState> frameState();
  Future<void> startDrag();
  Future<void> setTitle(String title);
  Future<void> setPreventClose({required bool prevent});
  Future<void> setSkipTaskbar({required bool skip});
  Future<void> setAlwaysOnTop({required bool onTop});
  Future<void> setBounds(Rect bounds);
  Future<Rect> bounds();

  Stream<WindowFrameState> frameChanges();
  Stream<void> closeRequests();

  /// Cada vez que esta janela volta a ser a janela em foco.
  ///
  /// Existe por causa de permissão. O usuário concede ou revoga FORA do app —
  /// nos Ajustes do sistema — e volta; sem um sinal na volta, o app continua
  /// dizendo "negado" até ser reiniciado, e a pessoa que acabou de liberar vê
  /// a tela insistir que não liberou. A janela é de quem sabe que ela voltou,
  /// então o sinal é daqui.
  ///
  /// [frameChanges] também carrega `focused` e não serve para isto: ele
  /// publica a cada redimensionamento e a cada maximizar, e uma releitura de
  /// permissão presa nele iria ao sistema durante todo arrasto de borda.
  Stream<void> focusGains();
}
