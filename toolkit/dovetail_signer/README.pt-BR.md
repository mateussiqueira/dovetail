**Português** · [English](README.md)

# dovetail_signer

> Assina e notariza o que o build já produziu. Roda **depois** do build, nunca dentro — e não empacota nada.

## Por que é um package separado do bundler

A regra "assinatura roda depois do build" só é de verdade se o bundler **não puder** assinar. No mesmo package, alguém liga um no outro em seis meses e o acoplamento volta — que é exatamente o que hoje amarra o instalador ao `cargo tauri build`.

O `dovetail_bundler` não depende deste package. Ele não tem como assinar.

## A política é o produto aqui

As falhas que o levantamento do Tauri achou não são de ferramenta, são de **política**: avisar onde devia parar. Cada uma virou teste.

| No Tauri | Aqui |
|---|---|
| chave que não corresponde à pública → aviso, build passa, release que ninguém aceita | conjunto de credencial **pela metade é erro fatal**, mesmo em build local |
| `CI=true` sem senha → assume senha vazia em silêncio | senha não definida é **erro**; senha vazia só se definida explicitamente |
| credencial de notarização incompleta → aviso, entrega app não notarizado | erro fatal, com o nome de cada variável que falta |
| `codesign` sem `--timestamp` → "às vezes sim, às vezes não" | `--timestamp` em **toda** chamada |
| sem `timestampUrl` → `signtool` roda sem timestamp | ausência é **erro**, e não há default |
| um `entitlements.plist` para tudo, inclusive daemon | entitlements por caminho, e nunca em framework ou dylib |
| `TAURI_SKIP_SIDECAR_SIGNATURE_CHECK` pula a assinatura inteira | lista vazia de arquivos é **erro**, não sucesso silencioso |

E o inverso também é política: **build local não pede certificado**. Sem segredo, o artefato fica não assinado e a saída diz isso. Com `--require-signature`, que só a esteira passa, o mesmo caso vira erro.

## macOS

De dentro para fora, item por item, com `xattr -crs` antes — o Tauri cita o QA1940 da Apple para isso. Nunca `--deep`.

Ordena os alvos por profundidade, e assina o bundle **por último**. Só filhos diretos das pastas de código aninhado (`MacOS`, `Frameworks`, `PlugIns`, `Helpers`, `XPCServices`, `Libraries`), recursando em `.app` embutido.

Notarização: `ditto -c -k --keepParent --sequesterRsrc` — não `zip`, porque o comentário do Tauri registra que isso remove quase todo falso alarme —, então `notarytool submit --wait`, e `stapler staple` só se o status for `Accepted`.

O `.dmg` é o segundo selo. `MacosSigner.signFile` assina a imagem como arquivo plano — identidade e carimbo, sem hardened runtime nem entitlements, que são do código lá dentro — e `Notarizer.notarizeFile` a submete direto, sem `ditto`, grampeando o ticket na própria imagem: é ela que o usuário baixa e o Gatekeeper avalia ao montar. Pelo CLI, `--target macos --file x.dmg [--notarize]`; o `.app` continua sendo `--bundle`, e os dois nunca na mesma chamada.

## Windows

`signtool sign /fd sha256 /sha1 <thumbprint> /tr <url> /td sha256 <arquivo>`. Certificado por thumbprint, nunca `.pfx` no comando: pressupõe o certificado já no store da máquina, que é o que a esteira faz importando antes.

## Linux

Não há portão. `SHA256SUMS` publicado, e o teste verifica com o `shasum -c` do sistema — inclusive que um artefato adulterado **falha** a verificação.

## A prova

O que vale mais aqui não é a contagem: **este package assina o
`vpn_desktop.app` que o repositório constrói de verdade**, de dentro para fora,
com identidade ad-hoc, e exige que o `codesign --verify --deep --strict` do
sistema aceite. Sem certificado nenhum.

Esse teste achou um bug real: a primeira versão tentava assinar **todo arquivo** dentro de `Frameworks/`, incluindo diretório de asset (`App.framework/.../um_design_system/assets/icons/nav`), e o `codesign` recusa com "bundle format unrecognized". Assina-se o bundle do framework, não o conteúdo dele.

## Uso

```bash
dart run dovetail_signer --target macos --bundle build/macos/.../App.app --notarize
```

```bash
dart run dovetail_signer --target windows --file dist/app.exe --file dist/helper.exe --require-signature
```

```bash
dart run dovetail_signer --target linux --file dist/app.deb --out-dir dist
```

## O que falta

- **Assinatura GPG destacada** do `SHA256SUMS` no Linux.
- **Keychain temporário** no runner macOS, a partir de certificado em base64.
- ~~**Ordem no Windows**~~ — resolvida na esteira, que é onde a ordem mora. O
  `ship` no Windows emite **duas** assinaturas: `sign --directory` sobre o
  payload antes do `bundle`, e `sign --file` sobre o instalador depois. Assinar
  só o instalador produz um arquivo que passa pelo SmartScreen e então deposita
  executáveis sem assinatura no disco de quem instalou — pior que não assinar,
  porque parece certo. No macOS também são duas, por outro motivo: o `.app` de
  dentro para fora (o selo cobre o conteúdo) e depois o `.dmg`, porque o
  Gatekeeper avalia a imagem ao montar e a notarização é dela também. O Linux
  não assina binário nenhum.

  O que ainda não existe é o package **recusar** sozinho um instalador de
  payload não assinado: verificar isso exige abrir o instalador, e nenhuma
  máquina aqui roda Windows para provar que a leitura está certa.
