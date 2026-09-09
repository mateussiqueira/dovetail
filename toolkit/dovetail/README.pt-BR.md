**Português** · [English](README.md)

# dovetail

Uma dependência para tudo que o app **roda**.

A pesquisa sobre o que já existe no ecossistema Flutter desktop deu sempre na
mesma resposta: as peças estão todas lá — `window_manager`, `tray_manager`,
`hotkey_manager`, `auto_updater`, Fastforge — só que cada uma é de um autor, com
a sua configuração e o seu ciclo de release. O `awesome-flutter-desktop`, que é
a lista canônica, não tem sequer categoria para assinatura de código. O valor do
Tauri nunca foi uma peça: foi um CLI e um arquivo.

```yaml
dependencies:
  dovetail: ^0.1.0
```

```dart
import 'package:dovetail/dovetail.dart';
```

## O que entra

| pacote | o que traz |
|---|---|
| `dovetail_platform_channel` | janela, tray, painel ancorado, instância única, deep link, notificação, login item |
| `dovetail_shortcut_channel` | atalho global, via a mesma crate `global-hotkey` que o Tauri usa |
| `dovetail_updater` | manifesto, download com teto, verificação minisign, instalação nos três SOs |
| `dovetail_form_validation` | as sete regras de formulário, com falha que diz qual quebrou |
| `dovetail_process_runner` | o runner que os instaladores recebem |

## O que fica de fora, de propósito

`dovetail_bundler`, `dovetail_signer` e `dovetail_cli` **não** entram. Empacotar e
assinar acontece na máquina de release, nunca dentro do app; arrastá-los para cá
colocaria uma cadeia de assinatura de código dentro de todo build de usuário.
Esses três já têm um ponto de entrada, e é o `dovetail_cli`.

`desktop_core_bridge` também fica de fora: ele carrega a API Rust de um produto
específico, e um package do toolkit não conhece produto nenhum.

## O que isso não resolve

Ter um barril não torna pronto o que está atrás dele. Cada package documenta o
que prova nesta máquina e o que precisa de outro sistema operacional; o barril
não muda uma linha disso.
