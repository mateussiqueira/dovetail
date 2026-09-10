#include <windows.h>

#include "dovetail_system_appearance.h"

// O Windows guarda a preferencia de tema numa chave de registro, e a AUSENCIA
// dela e informacao — nao um erro.
//
// `AppsUseLightTheme` so passa a existir quando o usuario mexe no tema, ou
// quando a imagem do sistema ja vem com ele escrito. Numa instalacao limpa
// que nunca foi tocada a chave nao esta la, e o que o sistema quer e
// literalmente desconhecido. O Flutter responde `Brightness.light` nesse caso,
// que e indistinguivel de um usuario que escolheu claro; aqui os dois casos
// tem respostas diferentes, que e o ponto deste arquivo.
//
// `AppsUseLightTheme` e nao `SystemUsesLightTheme`: a primeira e o tema das
// APLICACOES, a segunda e o da barra de tarefas e do menu iniciar. Sao
// configuraveis em separado no Windows, e o que uma janela deve seguir e a
// primeira.

namespace {

constexpr wchar_t kPersonalizeKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr wchar_t kAppsUseLightTheme[] = L"AppsUseLightTheme";

}  // namespace

int32_t DovetailSystemAppearance(void) {
  DWORD value = 0;
  DWORD size = sizeof(value);
  DWORD type = 0;

  const LSTATUS status = RegGetValueW(
      HKEY_CURRENT_USER, kPersonalizeKey, kAppsUseLightTheme,
      RRF_RT_REG_DWORD, &type, &value, &size);

  if (status != ERROR_SUCCESS) {
    return DovetailAppearanceUnknown;
  }

  return value == 0 ? DovetailAppearanceDark : DovetailAppearanceLight;
}
