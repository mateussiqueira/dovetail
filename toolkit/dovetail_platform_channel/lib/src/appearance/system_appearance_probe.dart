import 'dart:ffi';
import 'dart:io';

import 'package:dovetail_platform_channel/src/appearance/system_appearance.dart';

typedef _AppearanceNative = Int32 Function();
typedef _AppearanceDart = int Function();

const String _symbol = 'DovetailSystemAppearance';

/// Pergunta ao sistema qual aparência ele pede.
///
/// # Por que existe nativo, num pacote que é fachada
///
/// Este pacote embrulha plugins do pub.dev, e a regra é não escrever nativo
/// quando alguém já escreveu. Aqui não havia: os plugins de tema que existem
/// devolvem claro/escuro, porque é o que o Flutter modela, e é justamente o
/// terceiro estado que se queria. Um wrapper sobre eles perderia o dado antes
/// de ele chegar.
///
/// # Como cada plataforma responde
///
/// | | fonte | quando responde `unknown` |
/// |---|---|---|
/// | macOS | `NSApp.effectiveAppearance` | só antes de a aplicação existir |
/// | Linux | portal XDG, e GSettings como reserva | `no preference`, ou sem sessão |
/// | Windows | `AppsUseLightTheme` no registro | a chave nunca foi escrita |
///
/// No macOS a pergunta praticamente sempre tem resposta; o caso de verdade é
/// Linux e um canto do Windows. Vale saber disso antes de concluir, do Mac,
/// que a sonda "não faz nada".
final class SystemAppearanceProbe {
  /// A sonda deste host.
  ///
  /// O símbolo é resolvido AGORA, e não a cada leitura. Não é otimização: é o
  /// que faz [isAvailable] responder a verdade. No macOS a biblioteca é o
  /// próprio processo, e abri-la sempre funciona — inclusive num
  /// `flutter test`, onde plugin nenhum está carregado. Uma sonda que
  /// perguntasse só "a biblioteca abriu?" diria "disponível" ali, e só
  /// descobriria o contrário ao ler.
  factory SystemAppearanceProbe({DynamicLibrary? library}) {
    final DynamicLibrary? opened = library ?? _open();
    if (opened == null) {
      return const SystemAppearanceProbe.absent();
    }
    try {
      return SystemAppearanceProbe._(
        opened.lookupFunction<_AppearanceNative, _AppearanceDart>(_symbol),
      );
    } on ArgumentError {
      // A biblioteca existe e o símbolo não. É o app construído antes desta
      // versão do pacote, e é exatamente quando "não sei" é a resposta certa.
      return const SystemAppearanceProbe.absent();
    }
  }

  const SystemAppearanceProbe._(this._ask);

  /// Uma sonda que não tem a quem perguntar.
  ///
  /// Para teste, e para host sem o nativo. [read] devolve
  /// [SystemAppearance.unknown] — o mesmo que um sistema sem preferência
  /// responderia, que é o valor com que quem chama já tem de saber lidar.
  const SystemAppearanceProbe.absent() : _ask = null;

  final _AppearanceDart? _ask;

  /// Se há nativo para perguntar.
  bool get isAvailable => _ask != null;

  /// A aparência agora.
  ///
  /// Nunca lança. Uma sonda de cor que derruba o app é pior do que uma que
  /// não sabe responder.
  SystemAppearance read() {
    final _AppearanceDart? ask = _ask;
    if (ask == null) {
      return SystemAppearance.unknown;
    }
    return SystemAppearance.fromNative(ask());
  }

  /// Como cada plataforma entrega o nativo.
  ///
  /// São três formas porque são três construções: no Windows o plugin vira uma
  /// DLL ao lado do executável; no Linux, um `.so` empacotado com o app; no
  /// macOS ele vira um `.framework` embutido, que o runner já carregou quando
  /// o Dart começa a rodar — por isso o símbolo é procurado no PROCESSO em vez
  /// de num arquivo. Abrir por caminho ali exigiria saber onde o bundle está,
  /// que muda entre app construído, `flutter run` e teste de integração.
  static DynamicLibrary? _open() {
    try {
      if (Platform.isWindows) {
        return DynamicLibrary.open('dovetail_platform_channel.dll');
      }
      if (Platform.isLinux) {
        return DynamicLibrary.open('libdovetail_platform_channel.so');
      }
      if (Platform.isMacOS) {
        return DynamicLibrary.process();
      }
    } on Object {
      return null;
    }
    return null;
  }
}
