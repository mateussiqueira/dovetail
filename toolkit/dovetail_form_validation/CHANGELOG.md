# Changelog

## 0.1.1 — 2026-09-09

Nada no código mudou. A 0.1.0 foi publicada com o README em português e com
avisos que deixaram de ser verdade no momento em que o pacote saiu — "parte do
dovetail, versionado só localmente" era um deles. A página do pub.dev é
congelada na versão publicada, então esta versão existe para substituir o que
ela mostra.

O que muda: README em inglês no caminho canônico, com o português ao lado em
`README.pt-BR.md` e um seletor de idioma no topo dos dois. A instalação passa a
mostrar a dependência publicada em vez de um caminho para dentro do monorepo.

---

## 0.1.0 — 2026-09-08

As sete regras de formulário do produto, portadas do front React que sai.

- `required`, `min`, `minTrimmed`, `email`, `sameAs`, `digits`, `pastDate` —
  compostas por `Field(...)` e por `ValidationComposite`, que para na primeira
  falha porque formulário com seis mensagens é formulário que ninguém lê até o
  fim. `failuresByField` marca todos os campos ruins com uma mensagem cada.
- A falha é **tipo selado**, não chave de tradução: o `AppLocalizations` gerado
  expõe getters e não busca por string, e devolver a mensagem pronta obriga a
  reconstruir o validador a cada troca de idioma. O `switch` que vira frase é da
  tela, e é exaustivo.
- `FieldIsTooShort` carrega mínimo e comprimido; `FieldHasWrongLength` carrega
  esperado e recebido — para a mensagem poder ser "faltam 3 caracteres".
- `digits` separa tamanho errado de caractere errado, que o front antigo tratava
  como a mesma coisa.
- `pastDate` recusa 30 de fevereiro. `new Date('1990-02-30')` rola para 2 de
  março e `DateTime.tryParse` faz igual, então aquele aniversário era aceito
  calado como um dia diferente do digitado.
- O regexp de e-mail veio caractere por caractere do front antigo: mudá-lo
  passaria a recusar contas que já existem, e isso é decisão de produto.
