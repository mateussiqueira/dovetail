#ifndef DOVETAIL_NOTIFICATION_PERMISSION_H_
#define DOVETAIL_NOTIFICATION_PERMISSION_H_

#include <stdint.h>

#if defined(_WIN32)
#include <wchar.h>
#endif

#if defined(__cplusplus)
extern "C" {
#endif

/* Igual a `dovetail_system_appearance.h`: o Windows exporta de uma DLL, e as
 * outras duas plataformas entram no binario do app. Aqui so o Windows exporta
 * simbolo — o macOS responde por canal de metodo, porque a autorizacao dele e
 * assincrona, e o Linux nao tem o que responder. */
#if defined(_WIN32)
#if defined(DOVETAIL_BUILDING_DLL)
#define DOVETAIL_PERMISSION_EXPORT __declspec(dllexport)
#else
#define DOVETAIL_PERMISSION_EXPORT __declspec(dllimport)
#endif
#else
#define DOVETAIL_PERMISSION_EXPORT __attribute__((visibility("default")))
#endif

/*
 * A permissao de notificar, como o Dart, o Objective-C e o C++ tem de conta-la
 * igual. O enum de Dart e `PermissionState`, e a ordem la e esta.
 *
 * Cinco valores porque um booleano junta os dois estados que pedem caminhos
 * opostos: `NotDetermined` ainda pode abrir o dialogo do sistema, `Denied`
 * nunca mais — o macOS nao reexibe o dialogo para quem ja respondeu, e a unica
 * saida e o painel de Ajustes. `Restricted` e o caso em que nem a pessoa
 * decide (politica de administrador, controle parental).
 *
 * `Unsupported` e o zero, e nao um erro: e o Linux, que entrega sem perguntar,
 * e e o app construido antes deste simbolo existir. Um valor nao inicializado
 * cai ai, que e a resposta que nao inventa nem permissao nem recusa.
 */
typedef enum {
  DovetailNotificationPermissionUnsupported = 0,
  DovetailNotificationPermissionNotDetermined = 1,
  DovetailNotificationPermissionGranted = 2,
  DovetailNotificationPermissionDenied = 3,
  DovetailNotificationPermissionRestricted = 4,
} DovetailNotificationPermission;

#if defined(_WIN32)
/*
 * O que o registro do Windows diz sobre os toasts deste AppUserModelId.
 *
 * Sincrono porque nao ha nada assincrono a fazer: o Windows nao tem dialogo de
 * permissao para notificacao. O usuario desliga o app na pagina de
 * notificacoes dos Ajustes, e isso vira uma chave. Ler uma chave e uma funcao
 * C que devolve um inteiro, que e exatamente o que o `ffiPlugin` deste pacote
 * ja atravessa.
 *
 * `app_user_model_id` e UTF-16, que e o que o Dart entrega com
 * `String.toNativeUtf16()` do pacote ffi — a mesma coisa que um `LPCWSTR`.
 */
DOVETAIL_PERMISSION_EXPORT int32_t
DovetailNotificationPermissionFor(const wchar_t *app_user_model_id);
#endif

#if defined(__cplusplus)
}
#endif

#endif
