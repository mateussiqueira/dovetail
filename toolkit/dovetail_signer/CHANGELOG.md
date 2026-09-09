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

Assina e notariza, depois do build e nunca dentro dele.

- `MacosSigner.signFile` e `Notarizer.notarizeFile`: o `.dmg` é assinado como
  arquivo plano (identidade e carimbo, sem hardened runtime nem entitlements,
  que são do código lá dentro) e notarizado direto, sem `ditto` — o ticket é
  grampeado na própria imagem, que é o que o usuário baixa e o Gatekeeper
  abre. `NotarizationStep.runOnFile` aplica o mesmo veredito de credenciais,
  e o CLI aceita `--target macos --file <dmg> [--notarize]`.

- `SigningPolicy` e `Credential`: um conjunto de credenciais meio configurado é
  fatal, e senha não definida nunca é assumida vazia.
- macOS: `MacosSigner`, `SignOrder.insideOut` assinando só os filhos diretos de
  pasta de código aninhado, `--options runtime` apenas em executável, e
  `Notarizer` sobre `notarytool` e `stapler`.
- Windows: `Authenticode`, onde URL de timestamp vazia é fatal em vez de virar
  um default.
- Linux: `ChecksumWriter`.
- Atualização: `UpdateSigner` sobre o `minisign` real, `UpdateSignature`, e
  `SecretKeyAccess` — chave sem senha precisa dizer isso com `UnencryptedKey`.
- `ProcessRunner` aceita `stdin`, porque o `minisign` recebe senha por lá e por
  nenhum outro lugar.
