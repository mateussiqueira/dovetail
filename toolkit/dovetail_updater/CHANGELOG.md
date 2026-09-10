# Changelog

## Não publicado

Os instaladores deixavam o diretório de rascunho para trás. No Windows, o
caminho do `.msi` — que é aguardado — retornava sem apagar; no Linux, o apagar
ficava depois do `await`, então um runner que lançava (pkexec ausente, pipe
quebrado) pulava a limpeza. Cada corrida de testes deixava vinte e poucos
`dovetail_update*` no temp do sistema; havia 91 nesta máquina.

O caminho do `.exe` (NSIS, lançado e nunca aguardado) **continua** deixando o
arquivo, de propósito e agora com teste: o instalador ainda o lê depois de este
processo ter retornado.

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

Lê o manifesto e verifica o artefato: assinatura minisign, comentário
confiável conferido, downgrade recusado.

- `HttpArtifactFetcher` segue os redirecionamentos **à mão**, recusando antes
  de pedir qualquer salto que saia do https — o `HttpClient` segue de https
  para http sem dizer nada, e um 302 para um espelho http entregaria o
  manifesto em texto claro com a cara de https. Seguir à mão é o que permite
  recusar antes: nada sai da máquina em claro. `Location` relativo, que é o
  caso comum num CDN, é resolvido contra a url atual e herda o https de quem
  redirecionou; um laço para no quinto salto, e um 3xx sem `Location` é
  recusado em vez de lido como corpo. O corpo de cada 3xx é drenado antes de
  qualquer recusa e **dentro** do limite de tempo: enquanto o `HttpClient`
  seguia os saltos, ele drenava dentro do `close()`, que esta classe já
  limitava — seguir à mão sem limitar o drain devolvia um jeito de o fetch
  pendurar para sempre (um 3xx que anuncia corpo e não manda byte), e deixava
  um socket preso em cada recusa. Um artefato cujo `Content-Length` passa do
  teto tem a conexão **descartada** em vez de drenada — drenar ali seria
  baixar justamente os bytes que o teto recusa —, e medido: de seis conexões
  presas para zero, com as mesmas seis recusas. O teto de meio de fluxo não
  precisava disso, e a medição é o que disse: sair do `await for` com exceção
  cancela a subscrição, e ali seis recusas usavam uma conexão.
- O `Accept` passa a ser `application/json, */*`: o mesmo método busca o
  manifesto e o `.tar.gz`, e pedir só json para um tarball autoriza um servidor
  rigoroso a responder 406 justamente no passo do download.
- `HttpArtifactFetcher` aceita `timeout`: vale para a conexão, para os
  cabeçalhos e para o intervalo entre dois pedaços do corpo, e estoura como
  `UpdateFailure` dizendo quanto esperou. Nulo (o padrão) mantém a espera do
  SO, que é o certo para um updater em segundo plano.

- `MinisignPublicKey`, `MinisignSignature`, `MinisignVerifier`: Ed25519 sobre
  BLAKE2b-512 quando prehashed, aceitando o texto cru e a dupla camada de base64
  que o parque escreve. Verifica também a assinatura global que liga o
  comentário confiável — o que a implementação de referência do Tauri não faz.
- `ManifestParser`, `UpdateManifest`, `PlatformRelease`, `PlatformKey`: os seis
  nomes de fio, com o ABI lido do que a VM reporta em vez de assumido como x64.
- `UpdatePolicy`: downgrade é fatal a menos que explicitamente permitido.
- `EndpointTemplate`: `{{current_version}}`, `{{target}}`, `{{arch}}`,
  `{{bundle_type}}`; não-https é recusado.
- `UpdateFlow` e `VerifiedArtifact`: só o download verificado produz o tipo que
  o instalador aceita.
- `MacosInstaller` e `WindowsInstaller`. O MSI vai para o `msiexec`, não é
  executado direto.
