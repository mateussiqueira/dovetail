#import <AppKit/AppKit.h>

#include "dovetail_system_appearance.h"

/*
 * A aparencia efetiva do app, que e a que o macOS acabou de aplicar.
 *
 * `effectiveAppearance` — e nao `NSUserDefaults` com `AppleInterfaceStyle` —
 * porque a segunda le a preferencia GLOBAL do usuario e ignora um app que
 * declarou `NSRequiresAquaSystemAppearance` ou que teve a aparencia forcada.
 * Quando as duas discordam, quem esta certa e a que desenhou a janela.
 *
 * `bestMatchFromAppearancesWithNames:` em vez de comparar o nome direto: a
 * aparencia efetiva pode ser uma variante (`NSAppearanceNameAccessibility
 * HighContrastDarkAqua`, por exemplo), e comparar por igualdade responderia
 * "nao sei" para um sistema que esta claramente escuro. Isto pergunta de qual
 * das duas ela mais se aproxima, que e a pergunta certa.
 *
 * Devolve `Unknown` so quando nao ha app ainda — antes de `NSApplication` ser
 * criada nao existe aparencia efetiva para ler. No macOS rodando, esta funcao
 * sempre sabe responder; o `Unknown` daqui e a inicializacao, nao o gosto do
 * usuario.
 */
int32_t DovetailSystemAppearance(void) {
  if (NSApp == nil) {
    return DovetailAppearanceUnknown;
  }

  NSAppearance *appearance = NSApp.effectiveAppearance;
  if (appearance == nil) {
    return DovetailAppearanceUnknown;
  }

  NSAppearanceName matched = [appearance bestMatchFromAppearancesWithNames:@[
    NSAppearanceNameAqua,
    NSAppearanceNameDarkAqua,
  ]];

  if ([matched isEqualToString:NSAppearanceNameDarkAqua]) {
    return DovetailAppearanceDark;
  }
  if ([matched isEqualToString:NSAppearanceNameAqua]) {
    return DovetailAppearanceLight;
  }
  return DovetailAppearanceUnknown;
}
