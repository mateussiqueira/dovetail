# Escrever o app com o dovetail

O `README.md` deste repositório descreve a **esteira**: como um projeto vira
`.dmg`, `.msi`, `.deb` assinados e um manifesto. Este documento é o outro lado —
como se escreve o aplicativo que a esteira empacota.

Tudo aqui foi conferido contra o código. Onde algo ainda não existe, está dito
que não existe, em vez de omitido.

---

## A fronteira, e por que ela é o assunto mais importante

O dovetail **expõe capacidade e devolve evento. Ele não decide.**

Isso não é modéstia de biblioteca: é a regra que evita o problema que fez sair
do Tauri. O exemplo mais curto:

```dart
platform.window.closeRequests().listen((_) => platform.window.hide());
```

`closeRequests()` é um `Stream`. **Fechar para a bandeja é política**, e política
é do app. Se o package escondesse a janela sozinho, o dia em que o produto
quisesse perguntar antes viraria um fork.

A mesma regra vale em toda parte:

| o dovetail dá | quem decide |
|---|---|
| o pedido de fechar a janela | esconder, perguntar, ou sair |
| o comando clicado na bandeja | o que cada comando faz |
| a falha tipada do núcleo Rust | a frase que aparece na tela |
| qual regra de formulário quebrou | a mensagem, e em qual idioma |
| o veredito de instância única | rodar, focar a outra, ou avisar |
| que existe versão nova | avisar, baixar sozinho, ou exigir |

Se em algum ponto o framework parecer que decidiu por você, isso é um bug — abra
uma issue em vez de contornar.

---

## O caminho mais curto que funciona

```bash
cd product/meu_app
dart run ../../toolkit/dovetail_cli/bin/dovetail.dart init
```

`init` lê o projeto e escreve o `dovetail.yaml` — identificador, nome, alvos,
chave de update. Depois, no `pubspec.yaml`:

```yaml
dependencies:
  dovetail:
    path: ../../toolkit/dovetail
```

```dart
import 'package:dovetail/dovetail.dart';
```

Uma importação traz janela, bandeja, painel ancorado, instância única, deep
link, notificação, atalho global, updater, validação de formulário e o runner de
processo. O que **não** entra é `dovetail_bundler`, `dovetail_signer` e
`dovetail_cli`: empacotar e assinar acontece na máquina de release, e arrastá-los
para cá colocaria uma cadeia de assinatura de código dentro de todo build de
usuário.

---

## O boot, e por que a ordem importa

```dart
Future<void> main() async {
  // 1. Antes de qualquer coisa cara. Uma segunda instância descobre que é
  //    segunda ANTES de abrir janela, carregar núcleo ou tocar o disco.
  final SingleInstanceVerdict verdict =
      await DesktopPlatformChannel.claimSingleInstance('com.example.app');
  if (!verdict.mayRun) {
    // Diga por que está saindo. Um `return` calado aqui é um app que "não
    // abre" com exit 0, sem uma linha de log — e a causa mais comum é outra
    // instância viva que recebeu este lançamento (argumentos e deep link
    // incluídos). Quem depura precisa ler isto no terminal.
    stderr.writeln(
      'another instance is already running; this launch was forwarded to it.',
    );
    return;
  }

  // 2. A janela e o resto do SO.
  final DesktopPlatform platform =
      await DesktopPlatformChannel.ensureInitialized(
    const DesktopAppSpec(
      window: WindowSpec(size: Size(1200, 720), minimumSize: Size(1024, 640)),
      applicationId: 'com.example.app',
      displayName: 'Exemplo',
      notificationGuid: '00000000-0000-0000-0000-000000000000',
    ),
  );

  // 3. O núcleo Rust, que é caro e pode falhar.
  await DesktopCoreBridge.ensureInitialized();
  final core = await RustCore.start();

  runApp(App(platform: platform, core: core));
}
```

O `stderr` do passo 1 vem de `dart:io`, e `Size` e `runApp` de
`package:flutter/material.dart` — o trecho mostra só o corpo do `main`, e a
única importação do dovetail é a da seção anterior.

Nenhum número acima é padrão do package. `1200x720` e o nome vêm do app, porque
tamanho de janela e nome são decisão de produto — e no white-label, decisão de
revenda.

**O passo 3 pode falhar, e falhar é um estado da interface.** Um app que trava
na tela de splash porque o núcleo não subiu é pior que um que mostra o motivo e
um botão de tentar de novo.

---

## Texto

As 818 chaves do produto já estão em `lib/l10n/app_{pt,en,es}.arb`, importadas do
front React por `tool/import_locales.dart`. O `AppL10n` sai do `flutter pub get`
— o Dart gerado **não é versionado**, porque manter dez mil linhas no diff por
causa de uma palavra não paga.

No `MaterialApp`:

```dart
MaterialApp(
  localizationsDelegates: AppL10n.localizationsDelegates,
  supportedLocales: AppL10n.supportedLocales,
  home: const HomePage(),
)
```

Na tela:

```dart
final AppL10n t = AppL10n.of(context);
Text(t.homeConnect);                    // "Conectar"
Text(t.homeExpiryTitle(dias));          // "Seu plano vence em 3 dia(s)"
```

**Para acrescentar uma chave**, escreva nos três `.arb` — o template é
`app_pt.arb`, que é a língua em que as frases foram escritas. `flutter test
test/l10n` recusa quando uma chave existe num idioma e não noutro, ou quando
muda de argumento entre idiomas: os dois erros compilam sem reclamar e aparecem
como texto em português na tela de alguém que pediu espanhol.

Os plurais entre parênteses — `dia(s)`, `servidor(es)` — vieram assim do front
antigo e ficaram assim de propósito. ICU faz melhor e nada impede, mas reescrever
vinte frases em três línguas é decisão de tradução.

---

## Formulário

```dart
final ValidationComposite regras = ValidationComposite(<FieldValidation>[
  ...Field('email').email().rules,
  ...Field('password').min(8).rules,
  ...Field('passwordConfirmation').sameAs('password').rules,
]);

final ValidationFailure? erro = regras.validate(<String, String?>{
  'email': emailController.text,
  'password': senhaController.text,
  'passwordConfirmation': confirmaController.text,
});
```

A falha diz **qual regra quebrou**, não a frase. A tela transforma em texto com
um `switch` exaustivo — sem `default`, para que acrescentar uma regra quebre em
tempo de compilação em vez de virar um texto vazio na frente de alguém. O
`toolkit/dovetail_form_validation/README.md` traz o `switch` inteiro, com as chaves de
`l10n` conferidas contra o `.arb`.

---

## A ponte para o núcleo Rust

```dart
final session = await core.login(username: 'user', password: 'secret');

core.stateChanges().listen((TunnelStateChange change) => setState(...));

await core.connect(
  request: ConnectRequest(
    serverId: (await core.listServers()).first.id,
    splitTunnel: SplitTunnelRule(
      mode: SplitTunnelMode.everything,
      values: const <String>[],
    ),
    killSwitch: true,
  ),
);
```

**O erro chega tipado.** Não existe prefixo de texto para procurar:

```dart
try {
  await core.listServers();
} on CoreFailure catch (failure) {
  switch (failure.kind) {
    case CoreFailureKind.tooManyRequests:  // aguarde e tente de novo
    case CoreFailureKind.transport:        // não chegou ao backend
    case CoreFailureKind.unauthorized:     // a sessão morreu
    // ...
  }
}
```

Dos 51 métodos públicos do `CoreHandle`, **50 atravessam para o Dart** — o único
de fora é o construtor, e um teste prende isso: o núcleo crescer sem a ponte
acompanhar é o único sentido que o compilador não pega.

A ponte **não decide nada**: não valida, não orquestra, não guarda estado de
fluxo, não sabe em que ordem as telas acontecem. Cada método é um repasse e cada
tipo é um espelho.

### Se você for mexer no Rust, deixe isto rodando

```bash
cd product/desktop_core_bridge && flutter_rust_bridge_codegen generate --watch
```

O Dart em `lib/src/rust/` é gerado. Sem o watch, o precipício é este: você
acrescenta `pub fn nova_coisa()` em `rust/src/api/`, o `cargo check` passa, o
app compila, os testes passam — **e o método não existe do lado Dart**. Não há
erro em lugar nenhum. Você vai procurar por que `core.novaCoisa()` não existe, e
a resposta é "rode o codegen".

Isso foi medido, não suposto. `dart tool/verify.dart frb` é a rede: ela gera,
compara, restaura a árvore e diz o comando.

E o hot reload atravessa a ponte — 48 ms, restart em 352 ms — mas **só o Dart**.
Mudança em Rust pede rebuild, e isso é FFI, não configuração.

---

## Atalho global

```dart
final List<ShortcutOutcome> resultados = await surface.bind(<ShortcutRequest>[
  ShortcutRequest(
    name: 'toggle',
    chord: ShortcutChord.parse('CommandOrControl+Shift+V'),
  ),
]);

for (final ShortcutOutcome resultado in resultados) {
  switch (resultado) {
    case ShortcutBound():
      break;
    case ShortcutRefused(:final ShortcutRefusal reason, :final String detail):
      // `reason` é enum — sessionUnsupported, takenBySystem, alreadyBound…
      // `detail` é a frase que nomeia o caso concreto.
      mostrarAviso(reason, detail);
  }
}

surface.presses().listen((ShortcutPress press) {
  if (press.pressed) alternarJanela(press.name);
});
```

**A recusa é dado, não exceção.** Em Wayland o package reporta
`ShortcutBackend.waylandPortal` com `available: false` e **nomeia a sessão** —
porque um atalho que reporta sucesso e nunca dispara custa mais caro que um que
diz não. No macOS o backend é o Carbon depreciado de propósito: ele não pede
permissão de privacidade nenhuma, enquanto `CGEventTap` exigiria pedir, num
cliente de VPN, a permissão de um keylogger.

---

## Atualizar

```dart
final UpdateFlow flow = UpdateFlow(
  fetcher: HttpArtifactFetcher(),
  publicKey: release.publicKey,
  platformKey: PlatformKey.current().wireName,
);

final UpdateCheck check = await flow.check(
  endpoints: <String>[release.endpoint],
  installed: Version.parse(release.version),
);

if (check.shouldUpdate) {
  final VerifiedArtifact artefato = await flow.download(check.manifest!);
  final InstallOutcome desfecho = await InstallerForHost.resolve(
    runner: const SystemProcessRunner(),
    installedPath: Platform.resolvedExecutable,
  ).install(artefato);

  // Os dois desfechos são diferentes, e confundi-los deixa o usuário olhando
  // uma janela que já não é o app que ele instalou.
  switch (desfecho) {
    case InstallOutcome.installedRestartNeeded:  // troque quando ele deixar
    case InstallOutcome.installerLaunchedAppMustExit:  // saia agora
  }
}
```

`download` só devolve `VerifiedArtifact` depois de a assinatura minisign passar,
o comentário confiável bater e o downgrade ser recusado. Endpoint que não seja
`https` é recusado antes de qualquer coisa: **o manifesto não é assinado**, então
a integridade dele repousa inteiramente no transporte.

Antes de confiar num endpoint, pergunte a ele:

```bash
dovetail probe --url https://api.exemplo.com/manifest/darwin \
  --public-key keys/update.pub --installed 1.0.0 --download
```

O `probe` usa o **mesmo** parser, a mesma política e o mesmo verificador que o
app carrega. Verde não é opinião sobre o formato: é o cliente dizendo sim.

A chave que o app confia e o endpoint que consulta não são constantes suas:
leia-os com `String.fromEnvironment('dovetail.update.public_key')` e
`'dovetail.update.endpoint'`, com os padrões do produto como `defaultValue`. O
`dovetail build` embute o que o `dovetail.yaml` declara, então o mesmo arquivo
que assina o release decide em quem o app confia — e um build de staging aponta
para um host de staging sem tocar no app. `flutter run` sem o dovetail fica com
os padrões.
Contra um endpoint que não responde ele desiste em 15 s e diz isso, em vez de
esperar o que o sistema esperar; `--timeout <s>` muda o prazo, e `0` devolve a
espera do sistema.

---

## Publicar

```bash
dovetail ship            # a esteira inteira, a partir do dovetail.yaml
dovetail ship --dry-run  # imprime os passos e não roda nenhum
```

O `ship` monta a esteira como **dado** e imprime antes de rodar. Medido nesta
máquina: `.app` de 82,9 MB → dmg de 33 MB → manifesto assinado que o `minisign`
de referência aceita.

Sem `APPLE_SIGNING_IDENTITY` o passo de assinar **diz que o artefato fica sem
assinar** e segue, em vez de fingir.

---

## Onde o dovetail vai te dizer não

Vale conhecer antes de bater:

- **Endpoint `http`.** Recusado, com o motivo escrito.
- **Assinatura no manifesto como caminho ou URL.** Recusado: seria silenciosamente
  inverificável.
- **Downgrade.** É erro, não escolha do cliente. Liberar exige pedir de propósito.
- **`.app` sem `LSMinimumSystemVersion`.** O dmg recusa: sem a chave, um Mac
  antigo abre o app e morre num símbolo ausente.
- **Chave de desenvolvimento com endereço de produção.** Recusado — é a
  combinação que produz artefato publicável e inútil.
- **Atalho em Wayland.** Recusado com a sessão nomeada, em vez de aceito e mudo.
- **Duas releases para a mesma plataforma no mesmo manifesto.** Recusado, em vez
  de a segunda substituir a primeira em silêncio.
- **`dovetail keygen` sobre um par existente.** Recusado, porque a recuperação é
  reinstalar em todas as máquinas.

---

## O que ainda não existe

- **Rodar em Windows e em Linux.** O guarda de instância única em C++ compila
  pelo mingw e os símbolos batem com o que o `dart:ffi` procura; o `XGrabKey` do
  Linux nunca executou. Compila não é funciona.
- **Instalador de atualização no Linux.** Existe para macOS e Windows. No Linux a
  atualização é o gerenciador de pacotes da distro — isso é decisão, não lacuna.
- **Swift Package Manager nos plugins Rust.** Resolvido: XCFramework
  pré-construído como `binaryTarget` (`tool/build_xcframework.sh`); o podspec
  fica como fallback CocoaPods.
- **`mobile_scanner` em Windows e Linux.** Chega pelo barril do design system,
  que exporta `qr_scanner_view`, e não tem implementação nesses dois. O produto
  desktop não tem função de QR — zero das 818 chaves menciona uma —, então nada
  chama, mas a dependência viaja. Quem nomeia a lacuna a cada execução é
  `dart tool/verify.dart cross`; a correção é no repositório do design system.
- **Diálogo nativo de arquivo e clipboard em desktop.** Medido em pub.dev
  (jun/2026). `file_selector` (flutter.dev) cobre Linux, macOS e Windows.
  `super_clipboard` (nativeshell.dev, Rust por baixo) cobre Linux, macOS e
  Windows. `pasteboard` é alternativa mais simples com cobertura igual. Não é
  lacuna: o dovetail não precisa de plugin próprio para isso — basta depender
  desses pacotes quando a UI desktop precisar de seletor de arquivo ou acesso
  ao clipboard.

---

## Quando algo não bater com este documento

Ele foi escrito conferindo cada nome contra o código, e cada número contra uma
medição. Se divergir, **o código está certo e este arquivo está velho** — e vale
mais corrigir o arquivo do que contornar.
