**Português** · [English](README.md)

# dovetail_bundler

> Empacota um app Flutter desktop com núcleo Rust, chamando a ferramenta de cada plataforma. No lugar do bundler do Tauri.

O bundler do Tauri não empacota: ele **orquestra ferramenta alheia**. Chama `makensis` no Windows, WiX para MSI, `hdiutil` no macOS, `linuxdeploy` para AppImage — e `.deb`/`.rpm` ele nem chama nada, reimplementou em Rust porque é `ar` + `tar` + `md5`. Este package faz o mesmo, em Dart.

Por que Dart: é a linguagem da equipe daqui para frente, o `cargokit` que já usamos para compilar o Rust é exatamente isso, e — o que decide — **os modos de falha do Tauri são de lógica, não de ferramenta**. Ordem errada de `!addplugindir`, aviso onde devia ser erro, timestamp ausente. Isso se pega com teste; três scripts de shell divergentes não têm teste.

## Estado

| Alvo | Situação | O que se prova aqui |
|---|---|---|
| Windows, NSIS | **construído aqui**, com ressalva | ordem do script, escape, staging, invocação. Compila no macOS com `unicode: false`; o stub Unicode estoura em `std::bad_alloc` no arm64 |
| Windows, MSI | **construído aqui** | dois backends: `wix` no Windows, `wixl` em qualquer outro host. O `.wxs` gerado é validado por `xmllint`, o GUID tem golden test, e o MSI produzido é conferido com `msiinfo` e `msiextract` |
| macOS, `.dmg` | escrito | recusa um `.app` que não carrega as arquiteturas prometidas, antes do `hdiutil` |
| macOS, `.app.tar.gz` | escrito | o bundle assinado na raiz do tar, sem entradas `._*` (`COPYFILE_DISABLE`); é o que o updater extrai e o manifesto publica — `bundle --macos-format tar` |
| macOS, `.app` universal | escrito | `UniversalBundle` funde dois builds de arquitetura única, provado com `rustc` e `lipo` de verdade |
| Linux, `.deb` | escrito | lido pelo `ar` e `tar` do sistema, com modo de arquivo e scripts de manutenção |
| Linux, `.rpm` | escrito | spec e scriptlets; `rpmbuild` local só conhece `aarch64` |
| Ícones | escrito | o `.icns` desmontado pelo `iconutil` da Apple, o `.ico` lido pelo `file` |

Contagem de teste não fica escrita aqui, porque envelhece. `dart test` diz.

## As armadilhas do Tauri que aqui são erro fatal

Um levantamento do Tauri como arte anterior achou uns 30 avisos que eles pagaram. Três viraram teste:

**`!addplugindir` antes de qualquer `!include`.** Fora do topo absoluto, o `makensis` cai em silêncio para as DLLs **não assinadas** do toolset, apesar de a etapa de assinatura ter passado. Foi bug em produção lá. Um teste compara a linha do `!addplugindir` com a do primeiro `!include`.

**Metadado de build não numérico é erro, não zero silencioso.** O Tauri troca `1.2.3+abc` por `0` no `VIProductVersion` com um aviso e segue. `AppVersion.parse` recusa, e a mensagem diz o que fazer.

**`DovetailStrContains` existe duas vezes, e tem que existir.** O NSIS recusa
`Call` numa seção de desinstalação a menos que a função se chame
`un.algo` — então o corpo é instanciado com e sem o prefixo, e
`CheckIfAppIsRunning` recebe qual usar. Sem isso o script gerado **não
compilava em host nenhum**, Windows incluído; o estouro do stub Unicode no
arm64 escondia o erro real atrás de um crash mais cedo.

**O stub Unicode não compila no Apple silicon.** O `makensis` 3.12 estoura em
`std::bad_alloc` ao escrever a saída, num script de quatro linhas, e compilar da
fonte não muda. Com `unicode: false` ele compila, ao custo real de um
instalador ANSI: caminhos e strings são lidos na code page do sistema, e uma
máquina cujo caminho de instalação está fora dela instala no lugar errado. A
alternativa sem ressalva é o MSI, que o `wixl` constrói em qualquer host.

**`CheckIfAppIsRunning` imediatamente depois do `NSIS_HOOK_PREINSTALL`.** Essa ordem foi corrigida por bug reportado duas vezes no Tauri. Um teste exige que só o `!endif` fique entre as duas linhas.

## O `hooks.nsh` atual passa intacto

Os quatro ganchos têm o mesmo nome e a mesma posição do template do Tauri — `NSIS_HOOK_PREINSTALL`, `POSTINSTALL`, `PREUNINSTALL`, `POSTUNINSTALL`, todos guardados por `!ifmacrodef`. Na migração medida aqui, 280 linhas de um `installer/hooks.nsh` existente, que instalam e registram um serviço privilegiado, entraram sem alteração.

E não há dependência do plugin da Tauri: **medido que aquele hook usa só `nsExec` e `taskkill`**, ambos nativos. A macro `CheckIfAppIsRunning` daqui é implementada com `nsExec` + `tasklist`, sem `nsis_tauri_utils.dll`.

## Uso

```bash
dart run dovetail_bundler \
  --product-name "Example" \
  --manufacturer "Example Ltd" \
  --identifier com.example.app \
  --version 1.2.3+47 \
  --main-binary example \
  --app-dir build/windows/x64/runner/Release \
  --out-dir dist \
  --hooks installer/hooks.nsh
```

Escreve o caminho do instalador na saída padrão. Falha com código 1 e uma mensagem que traz o remédio.

## O dmg recusa um `.app` que não diz de qual macOS precisa

`LSMinimumSystemVersion` é a única coisa que impede um Mac antigo de abrir um
binário que ele não roda. Sem a chave o app abre e morre num símbolo ausente, o
que chega até nós como *"ele só fecha"* e chega até quem usa como nada.

Antes do `hdiutil`, não depois — dmg que existe é dmg que alguém sobe. Três
recusas: bundle sem a chave; bundle com a chave carregando
`$(MACOSX_DEPLOYMENT_TARGET)` **por expandir**, que o macOS lê como versão
nenhuma; e bundle que discorda do que a release declara, dizendo qual dos dois o
sistema obedece.

O Xcode preenche a chave a partir de `MACOSX_DEPLOYMENT_TARGET`, então projeto
correto já tem uma — isto existe para o dia em que alguém editar o template. O
app que este repositório constrói carrega `10.15`, e um teste confere isso
contra o bundle de verdade.

## O que não está provado aqui

**Que o `makensis` aceita o script gerado.** A estrutura é testada, mas validade de NSIS só se prova compilando — e o `makensis` 3.12 do Homebrew em arm64 macOS **aborta com `std::bad_alloc` até no script mínimo de quatro linhas**. O teste sonda usabilidade, não presença: se o `makensis` local não compila um script trivial, ele é marcado como pulado com esse motivo, em vez de dar um verde falso.

Essa prova pertence a um runner Windows, que é onde o instalador importa.

## Assinatura

Não está aqui, de propósito. Assinatura é passo **depois** do build, nunca dentro — o acoplamento inverso é o que hoje amarra o instalador ao `cargo tauri build`. Sem segredo, artefato não assinado e um aviso; com `--require-signature`, que só a esteira passa, o mesmo aviso vira erro.
