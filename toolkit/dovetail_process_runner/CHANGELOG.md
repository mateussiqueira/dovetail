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

Roda um processo e devolve o que ele disse, com dublê no lugar para os testes.

- `SystemProcessRunner` aceita `onStdout`/`onStderr`, chamados com cada
  pedaço assim que chega — o resultado continua inteiro no fim. A constante
  `SystemProcessRunner.echoing` repassa o filho ao terminal ao vivo; é o que o
  `dovetail build` usa para o `flutter build` não parecer travado.

- `ProcessRunner` é interface, então todo bundler, signer e installer recebe uma
  pelo construtor e o teste prende os argumentos — não o resultado de ter
  rodado uma ferramenta que na máquina de quem lê pode nem existir.
- A drenagem de `stdout` e `stderr` começa **antes** de qualquer escrita em
  `stdin`. A ordem inversa passa em todo teste pequeno e trava quando a saída
  passa do cano do SO; três testes prendem isso com saída grande de verdade.
- `stdin.close()` é incondicional: o `minisign` não termina com o descritor
  aberto, mesmo quando não havia nada a escrever.
- `timeout` mata com `SIGKILL`, espera o `exitCode` de verdade, dá 250 ms de
  folga para a drenagem e lança `ProcessTimeout` carregando o que o processo
  tinha dito até ali — que é onde está a pista.
- `firstDiagnostic` prefere `stderr`, cai para `stdout` e, com os dois vazios,
  diz o código de saída, em vez de devolver string vazia como motivo.
- `ProcessLauncher.launch` solta o processo e devolve o pid: o `.msi` substitui
  o executável que está rodando, então esperar por ele é esperar por um
  processo que só termina depois de matar quem espera.
- `runInShell` é `false` e não é configurável.
