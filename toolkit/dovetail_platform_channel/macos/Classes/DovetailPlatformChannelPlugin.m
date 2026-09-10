#import "DovetailPlatformChannelPlugin.h"

#import <UserNotifications/UserNotifications.h>

#include "dovetail_notification_permission.h"

static NSString *const kChannelName = @"dovetail/notification_permission";
static NSString *const kStateMethod = @"state";
static NSString *const kRequestMethod = @"request";

/*
 * A `UNAuthorizationStatus` traduzida para a tabela do dovetail.
 *
 * `Provisional` vira `Granted`: a autorizacao provisoria ENTREGA — em silencio,
 * direto na central — e para quem publica um aviso "entregou" e a resposta
 * certa. Trata-la como negada esconderia notificacoes que estao chegando.
 *
 * O caso desconhecido devolve `Unsupported`, e nao `Denied`. Uma versao futura
 * do macOS pode acrescentar um estado; ler um valor que este arquivo nao
 * conhece como recusa faria a UI mandar a pessoa desbloquear nas configuracoes
 * uma permissao que talvez esteja concedida.
 */
static int32_t DovetailPermissionFromStatus(UNAuthorizationStatus status) {
  switch (status) {
    case UNAuthorizationStatusNotDetermined:
      return DovetailNotificationPermissionNotDetermined;
    case UNAuthorizationStatusDenied:
      return DovetailNotificationPermissionDenied;
    case UNAuthorizationStatusAuthorized:
    case UNAuthorizationStatusProvisional:
      return DovetailNotificationPermissionGranted;
    default:
      return DovetailNotificationPermissionUnsupported;
  }
}

@implementation DovetailPlatformChannelPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel =
      [FlutterMethodChannel methodChannelWithName:kChannelName
                                  binaryMessenger:registrar.messenger];
  DovetailPlatformChannelPlugin *instance =
      [[DovetailPlatformChannelPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call
                  result:(FlutterResult)result {
  if ([kStateMethod isEqualToString:call.method]) {
    [self answerStateTo:result];
    return;
  }
  if ([kRequestMethod isEqualToString:call.method]) {
    [self requestThenAnswerTo:result];
    return;
  }
  result(FlutterMethodNotImplemented);
}

/*
 * O centro de notificacoes, ou nil quando nao ha bundle.
 *
 * `currentNotificationCenter` NAO devolve nil sozinho: ele derruba o processo
 * quando o executavel nao tem bundle identifier, porque o UserNotifications
 * identifica o app pelo bundle. Isso acontece rodando o binario solto, em
 * teste de unidade com host, e em qualquer coisa que nao seja um `.app`
 * assinado. Perguntar antes troca um crash por um `Unsupported`, que e a
 * verdade: nao ha app a quem conceder permissao.
 */
- (UNUserNotificationCenter *)center {
  if (NSBundle.mainBundle.bundleIdentifier == nil) {
    return nil;
  }
  return [UNUserNotificationCenter currentNotificationCenter];
}

- (void)answerStateTo:(FlutterResult)result {
  UNUserNotificationCenter *center = [self center];
  if (center == nil) {
    result(@(DovetailNotificationPermissionUnsupported));
    return;
  }

  [center getNotificationSettingsWithCompletionHandler:^(
              UNNotificationSettings *settings) {
    // O bloco chega numa fila qualquer do sistema. Um `FlutterResult` fora da
    // thread da plataforma e o tipo de corrida que aparece uma vez a cada mil
    // execucoes, na maquina de quem instalou.
    dispatch_async(dispatch_get_main_queue(), ^{
      result(@(DovetailPermissionFromStatus(settings.authorizationStatus)));
    });
  }];
}

/*
 * Pede a autorizacao e responde o estado que ficou.
 *
 * Nao devolve o `granted` do bloco: ele e um booleano, e um booleano nao
 * distingue "recusou agora" de "ja tinha recusado antes e o dialogo nem
 * apareceu". Reler as settings depois do pedido e uma viagem a mais e faz as
 * duas chamadas deste canal contarem a mesma historia — inclusive a provisoria,
 * que responde `granted = YES` e vale `Provisional`.
 *
 * O erro do bloco tambem nao vira falha do canal. Um app nao empacotado ou nao
 * assinado recebe "Notifications are not allowed for this application" aqui, e
 * o estado relido ja diz isso melhor do que uma excecao de plataforma diria.
 */
- (void)requestThenAnswerTo:(FlutterResult)result {
  UNUserNotificationCenter *center = [self center];
  if (center == nil) {
    result(@(DovetailNotificationPermissionUnsupported));
    return;
  }

  const UNAuthorizationOptions options = UNAuthorizationOptionAlert |
                                         UNAuthorizationOptionSound |
                                         UNAuthorizationOptionBadge;
  [center requestAuthorizationWithOptions:options
                        completionHandler:^(BOOL granted, NSError *error) {
                          (void)granted;
                          (void)error;
                          [self answerStateTo:result];
                        }];
}

@end
