#include <windows.h>

#include <string>

#include "dovetail_notification_permission.h"

// O Windows nao pergunta nada a ninguem sobre notificacao: um app com
// AppUserModelId registrado manda toasts desde o primeiro segundo. O que
// existe e o desligamento DEPOIS — a pagina Sistema > Notificacoes lista os
// apps que ja notificaram, e desligar um deles escreve `Enabled = 0` sob a
// chave dele.
//
// Dai a assimetria com o macOS, que vale entender antes de achar que falta
// codigo aqui: `NotDetermined` nao existe no Windows, porque nao ha o que
// determinar, e `request()` do lado Dart e a mesma leitura desta funcao.
//
// A AUSENCIA da chave e a resposta mais comum, e ela significa concedido: o
// app ainda nao foi desligado por ninguem. Ler ausencia como recusa faria toda
// instalacao nova nascer sem notificacao.
//
// A politica e lida antes, e nao depois. Um administrador que desliga toast na
// maquina inteira nao deixa registro na chave por app, e reportar `Denied` ali
// mandaria o usuario a uma pagina de Ajustes onde o controle esta travado.
// `Restricted` diz a verdade: nao e escolha dele.

namespace {

constexpr wchar_t kSettingsPrefix[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Notifications\\Settings\\";
constexpr wchar_t kEnabled[] = L"Enabled";

constexpr wchar_t kPolicyKey[] =
    L"SOFTWARE\\Policies\\Microsoft\\Windows\\CurrentVersion"
    L"\\PushNotifications";
constexpr wchar_t kNoToast[] = L"NoToastApplicationNotification";

bool ReadDword(HKEY root, const wchar_t *key, const wchar_t *value,
               DWORD *out) {
  DWORD size = sizeof(DWORD);
  DWORD type = 0;
  return RegGetValueW(root, key, value, RRF_RT_REG_DWORD, &type, out, &size) ==
         ERROR_SUCCESS;
}

// A politica da maquina primeiro, e a do usuario como segunda: a de maquina e
// a que um MDM escreve, e ela vence a preferencia de quem esta logado.
bool ToastsAreForbiddenByPolicy() {
  DWORD forbidden = 0;
  if (ReadDword(HKEY_LOCAL_MACHINE, kPolicyKey, kNoToast, &forbidden)) {
    return forbidden == 1;
  }
  if (ReadDword(HKEY_CURRENT_USER, kPolicyKey, kNoToast, &forbidden)) {
    return forbidden == 1;
  }
  return false;
}

}  // namespace

int32_t DovetailNotificationPermissionFor(const wchar_t *app_user_model_id) {
  if (app_user_model_id == nullptr || app_user_model_id[0] == L'\0') {
    // Sem AppUserModelId nao ha chave a consultar, e chutar `Granted` diria a
    // um app mal configurado que esta tudo certo com ele.
    return DovetailNotificationPermissionUnsupported;
  }

  if (ToastsAreForbiddenByPolicy()) {
    return DovetailNotificationPermissionRestricted;
  }

  const std::wstring key = std::wstring(kSettingsPrefix) + app_user_model_id;

  DWORD enabled = 0;
  if (!ReadDword(HKEY_CURRENT_USER, key.c_str(), kEnabled, &enabled)) {
    return DovetailNotificationPermissionGranted;
  }

  return enabled == 0 ? DovetailNotificationPermissionDenied
                      : DovetailNotificationPermissionGranted;
}
