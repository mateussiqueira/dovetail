**Português** · [English](README.md)

# dovetail_updater

> Lê o manifesto de atualização e verifica o artefato baixado — assinatura minisign, comentário confiável conferido, downgrade recusado.

## Corrigido: isto não é compatibilidade, é entrega

Este README abria dizendo que existiam instalações no campo confiando numa chave
minisign cravada no `tauri.conf.json`, e que a compatibilidade bit a bit era a
restrição externa dura do projeto. **Medido contra produção em 02/09/2026, não é
o caso.**

O `tauri_plugin_updater` estava registrado no `main.rs` do app Tauri e
**invocado em lugar nenhum** — zero chamadas em Rust, e o pacote JS nem está no
`package.json` do frontend. O que a tela recebe é um aviso com link. O `sha256`
que o endpoint devolve não é consumido por nada, e `mandatory` é fixo `false`.
**Não há verificação de assinatura nem de hash no caminho vivo.**

Isso não invalida uma linha deste package — muda a justificativa dele de *não
quebrar o que existe* para **entregar o que nunca existiu**. E a dupla camada de
base64, descrita abaixo, deixou de ser obrigação e virou escolha: mantida porque
custa nada e preserva a opção de um dia ligar o plugin.

O esquema de assinatura é o mesmo entre Tauri v1 e v2 — só o empacotamento dos
artefatos muda. Então a compatibilidade continua alcançável, com uma pegadinha
que quem reimplementa de cabeça erra.

## A dupla camada de base64

Nem o `.sig` nem o campo `pubkey` estão no formato minisign cru. Os dois são **base64 por cima do texto padrão do minisign**.

Conferido contra uma chave real: decodificar o base64 devolve

```
untrusted comment: minisign public key: 1234567890ABCDEF
RWQhww+7hfwEkazwMrOqcOeYRd+myNTpeJJP4bRWbnbMXV3T8ZSFPajp
```

E aquela segunda linha, decodificada, dá **42 bytes**: algoritmo `Ed`, mais um key id que, invertido, é precisamente o que o comentário declara. O formato está entendido byte a byte, não por analogia.

`MinisignPublicKey.parse` e `MinisignSignature.parse` aceitam as duas formas: o texto puro e o texto embrulhado em base64.

## A prova

**Assinatura feita pelo `minisign` de referência, verificada por este código.** O teste carrega um par de chaves e uma assinatura produzidos pela ferramenta oficial, e exige que a verificação passe — e que falhe quando um único byte do payload muda, quando a chave é outra, e quando o comentário confiável foi editado.

Descoberta pelo caminho: o minisign moderno assina **prehashed** por padrão. A assinatura real começa com `RUQ`, que decodifica para `ED`, e o comentário confiável diz `hashed`. Então a verificação passa por BLAKE2b-512 antes do Ed25519. Suportamos os dois: `Ed` sobre a mensagem crua, `ED` sobre o digest.

## Três coisas que fazemos e o Tauri não

**Verificamos o comentário confiável.** Ele carrega o timestamp e o nome do arquivo, e é assinado — mas o cliente do Tauri nunca confere. Sem isso, uma assinatura válida pode ser reaproveitada para outro nome de arquivo. Um teste edita `file:small.bin` para `file:malware.exe` e exige que a verificação recuse.

**Downgrade é erro, não escolha do cliente.** A assinatura sozinha não impede rollback: qualquer artefato mais antigo assinado com a mesma chave verifica. No Tauri a defesa é uma comparação client-side substituível. Aqui é a política que recusa, e liberar exige pedir de propósito.

**Um bloco de plataforma quebrado invalida o manifesto para todos.** Isso é comportamento do Tauri e está certo — um bloco malformado significa release publicada errada —, mas a mensagem aqui diz qual bloco e o que falta nele.

## O manifesto

Os dois formatos, distinguidos pela presença de `platforms`. Chave `OS-ARCH`. `signature` é o **conteúdo** do `.sig`, e um caminho ou URL ali é erro explícito, porque seria silenciosamente inverificável.

Variáveis do endpoint: `{{current_version}}`, `{{target}}`, `{{arch}}` e `{{bundle_type}}` — este último não aparece na doc do Tauri, só no código, e é o que permite servir a atualização certa para quem instalou `.deb` versus outro formato na mesma arquitetura.

Endpoint que não seja `https` é recusado: **o manifesto não é assinado**, então a integridade do redirecionamento repousa inteiramente no transporte.

## O que falta

- ~~**Instalador de Linux.**~~ Este item estava velho: o `LinuxInstaller` existe
  e tem 18 testes. Ele lê o formato pelo nome do artefato e faz o que cada um
  pede — `.deb` e `.rpm` vão ao gerenciador de pacotes por `pkexec` (e direto,
  sem pedir autorização, quando o processo já é root), e AppImage é substituído
  no lugar, com o anterior guardado e devolvido se a escrita falhar. Quem
  resolve os três é `InstallerForHost.resolve`, que **recusa por nome** o
  sistema que não tem instalador, em vez de baixar e verificar uma atualização
  que não sabe aplicar.
- **Rodar em Windows.** O `WindowsInstaller` nunca executou um instalador de
  verdade; o que está provado é qual executável ele chama e com quais
  argumentos.

## Qual instalador roda aqui

`InstallerForHost.resolve` escolhe pelo sistema em execução e **recusa** um
host sem instalador, em vez de devolver nulo. Um cliente que baixa, confere a
assinatura e então descobre que não sabe aplicar já disse ao usuário que há
versão nova.

No macOS ele resolve o caminho para o bundle: `Platform.resolvedExecutable`
aponta para dentro do `.app`, e trocar só aquele arquivo deixa um bundle cujo
selo não confere mais com o conteúdo. No Linux o caminho vem de `APPIMAGE` —
um `.deb` ou `.rpm` é substituído pelo gerenciador e não precisa de caminho
nenhum.

## Aplicar no Linux

`LinuxInstaller` separa os dois casos que o Linux tem. Um `.AppImage` é um
arquivo só: o instalador renomeia o que está rodando para `.previous`, escreve o
novo no lugar, marca executável e só então apaga o anterior — se a escrita
falhar, o anterior volta e a instalação segue de pé. Um `.deb` ou `.rpm` vai
para o gerenciador de pacotes via `pkexec`, que é quem pede a autorização;
`rpm --upgrade --replacepkgs` porque `-U` sai 2 quando a versão já está
instalada, que é exatamente o caso de repetir um update pela metade.

O que ainda não foi provado numa máquina Linux: se `dpkg`/`rpm` de fato aceitam
o pacote, e se `pkexec` sai 126 ao descartar o diálogo e 127 sem barramento de
sessão. A montagem do comando e a troca do AppImage são provadas aqui.

## O fluxo de ponta a ponta

`UpdateFlow` amarra as três etapas — `check`, `download`, `install` — e é o que
um cliente chama de verdade. O teste `test/update_flow_test.dart` cobre o
caminho inteiro com um `ScriptedFetcher` fake.

**`check`** consulta uma lista de endpoints em ordem e para no primeiro que
responde. Um endpoint que devolve `204` é lido como "sem atualização" e a
consulta **para ali** — não tenta o próximo (`update_flow_test.dart:109`). Um
endpoint fora do ar ou com status de erro (ex.: `500`) faz o fluxo cair para o
próximo (`update_flow_test.dart:89`, `:123`). Se todos falham, o erro diz
"every update endpoint failed" e carrega o motivo do último (`:137`). Sem
nenhum endpoint configurado, `check` recusa (`:65`).

**`download`** baixa o artefato apontado pelo manifesto, reporta progresso via
`onProgress` (`:184`) e **só devolve um `VerifiedArtifact`** — ou seja, o
artefato já passou pela verificação minisign. Um byte alterado no payload é
recusado com "does not match its signature" (`:207`), e um artefato que o
servidor não serve (ex.: `404`) também é recusado (`:233`).

**`install`** entrega o artefato verificado ao instalador da plataforma. No
macOS o teste de verdade troca o bundle: cria um `.app` com `version.txt`,
empacota um novo em `tar.gz`, instala e confere que o arquivo virou `2.0.0`
(`:287`). Um arquivo sem bundle é recusado com "Nothing was replaced" e o
bundle antigo fica intacto (`:338`), e nada sobra depois da troca — o
`.previous` é apagado (`:316`).

## O lado de escrita: `ManifestWriter`

O package não só lê o manifesto — ele também o **escreve**, e o teste
`test/manifest_writer_test.dart` garante que o que sai é exatamente o que o
parser aceita de volta (round-trip, `:23`).

As mesmas regras do parser valem na escrita, e são recusadas em vez de
silenciadas:

- uma versão que o cliente não consegue parsear (ex.: `banana`) é recusada com
  o aviso de que isso produziria "no update ever arriving" (`:39`);
- o mesmo `platformKey` duas vezes é recusado, não sobrescrito — "silently
  replace" (`:70`);
- assinatura vazia é recusada (`:89`);
- URL `http` (sem TLS) é recusada, porque o manifesto não é assinado e a
  integridade repousa no transporte (`:101`);
- nenhuma plataforma é recusado (`:119`);
- algo que não é uma assinatura minisign (ex.: um caminho `dist/app.dmg.minisig`)
  é recusado com "not a minisign signature" (`:199`).

Detalhes de formato: `notes` em branco não vira campo (`:129`), a saída é
determinística byte a byte (`:140`) e termina em nova linha, como um arquivo em
disco (`:148`). A assinatura é gravada **base64 por cima do texto minisign** —
e se já vier embrulhada, não é embrulhada de novo (`:158`, `:176`).

## `pub_date`: data de publicação estrita

`test/pub_date_test.dart` prova o parsing de `pub_date`. Uma data real passa
(`:12`), ausência fica `null` (`:19`), e o que não é data é **recusado**, não
lido como ausente — um typo não remove a data de publicação em silêncio
(`:23`). Campos fora do intervalo (mês 13, dia 30 de fevereiro) são recusados
em vez de rolados para uma data plausível (`:39`, `:55`, `:62`), e um dia
bissexto válido é aceito (`:69`). Valor só com data (sem hora) também passa
(`:76`).

## `PlatformKey`: os seis alvos e a arquitetura real

`test/platform_key_arch_test.dart` prova como o package decide qual artefato
pedir. A arquitetura vem do ABI que a VM reporta — `macos_arm64` → `arm64`,
`windows_x64` → `x64`, `linux_arm64` → `arm64` (`:6`). Uma string que não dá
para ler é recusada, porque o fallback anterior para `x64` baixava artefato
x86 numa máquina arm e reportava sucesso (`:21`). Os seis alvos — 3 sistemas ×
2 arquiteturas — têm nomes de fio distintos (`darwin-aarch64`,
`windows-x86_64`, `linux-aarch64`, etc., `:67`), e uma arquitetura sem nome no
protocolo é recusada (`:83`).

## O fetcher de verdade: HTTPS com loopback TLS

`test/http_artifact_fetcher_test.dart` exercita o `HttpArtifactFetcher` real
contra um servidor TLS de loopback montado com `openssl` (helper `_Loopback`),
em vez de um fake. É a prova de que o download de verdade respeita o transporte
HTTPS e reporta progresso — o resto do fluxo usa o `ScriptedFetcher` justamente
para isolar a lógica da rede.
