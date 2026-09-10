#ifndef DOVETAIL_SYSTEM_APPEARANCE_H_
#define DOVETAIL_SYSTEM_APPEARANCE_H_

#include <stdint.h>

#if defined(__cplusplus)
extern "C" {
#endif

/* O Windows exporta de uma DLL; macOS e Linux entram no binario do app. */
#if defined(_WIN32)
#if defined(DOVETAIL_BUILDING_DLL)
#define DOVETAIL_APPEARANCE_EXPORT __declspec(dllexport)
#else
#define DOVETAIL_APPEARANCE_EXPORT __declspec(dllimport)
#endif
#else
#define DOVETAIL_APPEARANCE_EXPORT __attribute__((visibility("default")))
#endif

/*
 * A aparencia que o sistema pede.
 *
 * `Unknown` NAO e um erro: e a resposta legitima de um sistema que nao tem
 * preferencia declarada. O portal XDG do Linux tem esse valor com esse nome
 * (`no preference`), e o Windows fica assim quando a chave do tema nunca foi
 * escrita. O Flutter colapsa os dois em `Brightness.light`, e e exatamente
 * essa distincao que existir aqui recupera: quem chama decide o que fazer com
 * "nao sei", em vez de receber "claro" e nao poder saber a diferenca.
 */
typedef enum {
  DovetailAppearanceUnknown = 0,
  DovetailAppearanceLight = 1,
  DovetailAppearanceDark = 2,
} DovetailAppearance;

DOVETAIL_APPEARANCE_EXPORT int32_t DovetailSystemAppearance(void);

#if defined(__cplusplus)
}
#endif

#endif
