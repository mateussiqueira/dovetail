# dovetail_form_validation

> Parte do `dovetail`. Versionado só localmente.

> As sete regras de formulário do produto, um construtor para compô-las, e uma
> falha que diz **qual regra quebrou** em vez de uma mensagem que quem chama
> tem de acreditar.

Dart puro, sem Flutter. 29 testes em menos de um segundo.

## Por que a falha não é texto

O front React que este projeto substitui devolvia uma chave de tradução:
`"signup.errors.passwordShort"`. Em Dart isso não funciona — o `AppLocalizations`
gerado expõe **getters**, não busca por string, e não existe `t('chave')`.

As outras duas saídas também não servem. Devolver a mensagem já resolvida obriga
a reconstruir o validador toda vez que o idioma muda, e um validador construído
uma vez no controlador fica com o texto velho para sempre. Devolver um `bool`
perde qual das duas regras do campo falhou.

Então a falha é **tipo selado**:

```dart
sealed class ValidationFailure { final String field; }

final class FieldIsRequired      extends ValidationFailure {}
final class FieldIsTooShort      extends ValidationFailure { minimum, actual }
final class FieldIsNotAnEmail    extends ValidationFailure {}
final class FieldIsNotDigits     extends ValidationFailure {}
final class FieldHasWrongLength  extends ValidationFailure { expected, actual }
final class FieldsDoNotMatch     extends ValidationFailure { other }
final class FieldIsNotADate      extends ValidationFailure {}
final class FieldIsTooOld        extends ValidationFailure { earliestYear }
final class FieldIsInTheFuture   extends ValidationFailure {}
```

Quem transforma isso em frase é a tela, com um `switch` **exaustivo**:

```dart
String messageFor(ValidationFailure failure, AppL10n t) => switch (failure) {
  FieldIsRequired()      => t.feedbackRequiredFields,
  FieldIsTooShort()      => t.signupErrorsPasswordShort,
  FieldIsNotAnEmail()    => t.emailInvalid,
  FieldIsNotDigits()     => t.signupErrorsInvalidPin,
  FieldHasWrongLength(:final int expected) => t.emailCodeRequired(expected),
  FieldsDoNotMatch()     => t.signupErrorsPasswordMismatch,
  FieldIsNotADate()      => t.signupErrorsInvalidBirthday,
  FieldIsTooOld()        => t.signupErrorsInvalidBirthday,
  FieldIsInTheFuture()   => t.signupErrorsInvalidBirthday,
};
```

Sem `default`. Acrescentar regra aqui **quebra esse `switch` em tempo de
compilação**, em vez de cair num texto vazio na frente de alguém. E a falha
carrega os números que a produziram, então a mensagem pode ser *"faltam 3
caracteres"* e não *"muito curto"*.

Todas as chaves citadas existem em `lib/l10n/app_pt.arb` com essa assinatura,
conferidas contra o arquivo — `emailCodeRequired` é a única que recebe
argumento, e recebe o `n` que a própria falha carrega. As três últimas apontam
para o mesmo texto de propósito: o front antigo dava uma mensagem só para data
ruim, e separar isso é decisão de produto, não do porte. **A falha já distingue
as três**, então o dia em que essa decisão for tomada não custa nada aqui.

## Uso

```dart
import 'package:dovetail/dovetail.dart'; // sai pelo barril

final ValidationComposite senha = ValidationComposite(<FieldValidation>[
  ...Field('password').min(8).rules,
  ...Field('passwordConfirmation').sameAs('password').rules,
]);

final ValidationFailure? erro = senha.validate(<String, String?>{
  'password': controller.text,
  'passwordConfirmation': confirmController.text,
});
```

`validate` para na **primeira** falha, na ordem em que as regras foram
declaradas: formulário que mostra seis mensagens de uma vez é formulário que
ninguém lê até o fim.

Quando a tela precisa marcar todos os campos ruins ao mesmo tempo, e ainda
assim uma mensagem por campo:

```dart
final Map<String, ValidationFailure> porCampo =
    senha.failuresByField(valores);
```

## O mapa de entrada é `Map<String, String?>`

Ausente e `null` leem como vazio. É assim que formulário Flutter é de verdade —
`TextEditingController.text` —, e obrigar quem chama a normalizar isso é como
um `null` passa por válido.

## As sete regras

| construtor | recusa com |
|---|---|
| `.required()` | `FieldIsRequired` — só espaço em branco conta como vazio |
| `.min(n)` | `FieldIsTooShort` — o espaço em volta conta |
| `.minTrimmed(n)` | `FieldIsTooShort` — o espaço em volta não conta |
| `.email()` | `FieldIsNotAnEmail` |
| `.sameAs(outro)` | `FieldsDoNotMatch` |
| `.digits(n)` | `FieldHasWrongLength` ou `FieldIsNotDigits` |
| `.pastDate(ano)` | `FieldIsNotADate`, `FieldIsTooOld` ou `FieldIsInTheFuture` |

`min` e `minTrimmed` eram duas classes no front antigo; viraram uma com um flag,
porque a diferença entre elas é só se o espaço em volta conta.

## Três coisas que mudaram no porte, e por quê

**O regexp de e-mail veio caractere por caractere.** Não porque seja a melhor
expressão de um endereço — nenhum regexp é — mas porque mudá-lo passaria a
recusar contas que entraram pelo app antigo, e isso é decisão de produto, não
de porte.

**`digits` separa tamanho errado de caractere errado.** O front antigo devolvia
a mesma chave para as duas coisas. Um PIN de seis dígitos digitado com cinco é
um engano diferente de um digitado com uma letra, e quem digita merece saber
qual.

**`pastDate` recusa 30 de fevereiro.** `new Date('1990-02-30')` não falha: rola
para 2 de março. `DateTime.tryParse` faz exatamente igual. Então aquele
aniversário **era aceito, calado, como um dia diferente do digitado** — e o teste
que prova isso nomeia o bug antigo. A defesa é reformatar a data e comparar com
o que entrou.

## O que este package não faz

Não conhece `AppL10n`, não conhece widget, não conhece o produto. Ele diz qual
regra quebrou e com que números; a frase é da tela, e o idioma é do `l10n`.
