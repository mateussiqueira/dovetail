#import <FlutterMacOS/FlutterMacOS.h>

/*
 * O unico canal de metodo deste pacote.
 *
 * Todo o resto do nativo daqui e `ffiPlugin`: funcao C, inteiro de volta, sem
 * fila de mensagens. A permissao de notificacao nao cabe nessa forma —
 * `requestAuthorization` do `UNUserNotificationCenter` recebe um bloco de
 * conclusao e responde quando a pessoa clicar no dialogo, que pode ser nunca.
 * Uma funcao C que devolve int nao tem como esperar isso, e bloquear a thread
 * do Dart ate a pessoa decidir seria pior do que o canal.
 *
 * O pubspec declara `pluginClass` E `ffiPlugin: true` para o macOS por isso: o
 * simbolo da aparencia continua atravessando por FFI, e so esta parte usa o
 * canal.
 */
@interface DovetailPlatformChannelPlugin : NSObject <FlutterPlugin>
@end
