# Changelog

## 0.1.2 — 2026-09-18

O plist do daemon passa a sair com `StandardOutPath` e `StandardErrorPath`
apontando para `/var/log/<label>.log`. Sem as duas chaves o `launchd` manda
stdout e stderr para lugar nenhum: um daemon que não conecta não deixa nada
para ler na máquina de quem usa, e o defeito é indiagnosticável em campo.

O arquivo fica direto em `/var/log`, sem subdiretório — a rota `bundled` não tem
`postinstall` para criar um, e o `launchd` só cria o arquivo quando o diretório
pai já existe. Os dois geradores seguem a mesma convenção e o mesmo caminho:
`LaunchDaemon.render()`, para a rota `system`, e `DaemonEmbedder.plistFor()`,
para a `bundled`.

---

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

Empacota chamando a ferramenta de cada plataforma, e recusa antes de chamar.

- `AppArchiveBundler`: o `.app` assinado em `.app.tar.gz`, com o bundle na
  raiz — o artefato que o updater extrai e troca no lugar. O `.dmg` é para a
  primeira instalação; o updater não monta imagem. `COPYFILE_DISABLE=1` no
  `tar`, para o macOS não gravar entradas `._*` que quebrariam o selo do
  bundle ao extrair.

- `BundleSpec`, `AppVersion`, `InstallMode`, `StagedFile`.
- macOS, dmg: recusa um `.app` sem `LSMinimumSystemVersion`, com a chave por
  expandir, ou que discorde do que a release declara — antes do `hdiutil`,
  porque dmg que existe é dmg que alguém sobe.
- `TargetArch` e `TargetOs`: uma taxonomia só, carregando a grafia de cada
  ferramenta — `amd64` no Debian, `aarch64` no RPM, `x64` no WiX. 32 bits é
  recusado com o motivo escrito.
- Windows, NSIS: `NsisScript` com quatro pontos de gancho, `CheckIfAppIsRunning`
  por `nsExec` sem depender de plugin, idiomas vindos da spec.
- Windows, MSI: `MsiSpec`, `MsiComponentTree`, `WixSource`, `WixTool`. GUID de
  componente determinístico por UUIDv5, guarda que **aborta** contra instalação
  cruzada, e rollback agendado antes do trabalho.
- macOS: `DmgBundler`, `UniversalBinary` por `lipo`, `MachO` lido em Dart puro,
  e `BundleArchitectures`, que recusa um `.dmg` universal de binário magro.
- Linux: `DebBundler` com escritor `ar` próprio, `RpmBundler` sobre `rpmbuild`,
  `SystemdUnit`, `PolkitPolicy`, `ServiceScripts` e `DesktopEntry` com nome
  reverse-DNS.
- Ícones: `IconSource`, `IcoWriter`, `IcnsWriter`, `HicolorIcons` — os dois
  contêineres escritos em Dart, sem ferramenta externa.
