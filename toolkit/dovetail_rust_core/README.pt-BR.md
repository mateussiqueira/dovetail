**Português** · [English](README.md)

# dovetail_rust_core


> A camada de compatibilidade entre Dart e Rust. Não sabe o que é VPN, não sabe o que é revenda, não sabe o que é o seu app.

Todo projeto que põe Flutter na frente de um núcleo Rust reescreve as mesmas três peças, e erra as mesmas três. Este package existe para elas serem escritas uma vez e testadas uma vez.

## O que ele resolve

**A ponte com o tokio.** O executor do `flutter_rust_bridge` não é um reator tokio. Um crate que usa `tokio::net` ou `tokio::time` — named pipe, unix socket, timer — quebra se rodar direto nele. `dovetail_rust_core::run_on_runtime` mantém um runtime multi-thread num `OnceLock` e faz `spawn` nele, devolvendo um `JoinHandle` que qualquer executor consegue aguardar.

**O consumidor lento de `broadcast`.** `receiver.recv()` devolve `Err(RecvError::Lagged)` quando o assinante fica atrás, e o canal **continua vivo**. Escrever `while let Ok(event) = receiver.recv().await` trata isso como fim de stream e congela a tela no último estado recebido. `dovetail_rust_core::pump` tolera `Lagged` e para só em `Closed`.

**A plataforma sem binário.** Chamar a ponte em Android, iOS ou web tem de dar um erro que se lê, não um `MissingPluginException` vindo de três camadas abaixo. `RustBridge.isSupported` responde antes de qualquer chamada nativa, e `ensureInitialized` é idempotente — e permite nova tentativa se a primeira falhar.

## O que ele não faz, por regra

Nenhuma regra de negócio de aplicação entra aqui. Nenhum DTO de domínio, nenhum endpoint, nenhuma validação, nenhuma dependência de crate de produto. Se um tipo deste package souber o nome de uma entidade do seu app, alguém errou.

A fachada tipada do seu núcleo Rust mora no **seu** package de ponte, que depende deste.

## Instalação

```yaml
dependencies:
  dovetail_rust_core: ^0.1.0
```

E no `Cargo.toml` do crate FFI do seu projeto:

```toml
dovetail_rust_core = { path = "caminho/para/dovetail_rust_core/rust" }
```

## Uso

Do lado Dart, embrulhando o `init` que o gerador produziu para o **seu** crate:

```dart
import 'package:dovetail_rust_core/dovetail_rust_core.dart';

final bridge = RustBridge(initializer: RustLib.init);

if (!bridge.isSupported) return;
await bridge.ensureInitialized();
```

Uma ponte que também vale em celular declara isso:

```dart
final bridge = RustBridge(
  initializer: RustLib.init,
  supportedPlatforms: <TargetPlatform>{...desktopPlatforms, ...mobilePlatforms},
);
```

Do lado Rust, na sua fachada:

```rust
use dovetail_rust_core::{pump, run_on_runtime, runtime};

async fn run<T, E, F>(future: F) -> Result<T, MyFailure>
where
    T: Send + 'static,
    E: Into<MyFailure> + Send + 'static,
    F: std::future::Future<Output = Result<T, E>> + Send + 'static,
{
    match run_on_runtime(future).await {
        Ok(Ok(value)) => Ok(value),
        Ok(Err(error)) => Err(error.into()),
        Err(bridge) => Err(MyFailure::from(bridge)),
    }
}
```

E para um stream de eventos:

```rust
runtime()?.spawn(async move {
    pump(source.subscribe(), |event| sink.add(MyEvent::from(event)).is_ok()).await;
});
```

## Superfície

| Lado | Item | O que é |
|---|---|---|
| Dart | `RustBridge` | sonda de plataforma + init idempotente |
| Dart | `UnsupportedPlatformException` | erro que diz a plataforma e o guarda a usar |
| Dart | `desktopPlatforms` · `mobilePlatforms` | conjuntos prontos |
| Rust | `runtime()` | o runtime tokio compartilhado |
| Rust | `run_on_runtime` | roda um future nele e devolve o valor |
| Rust | `pump` | loop de `broadcast` tolerante a atraso |
| Rust | `BridgeError` | runtime indisponível ou tarefa que morreu |

## Desenvolvimento

```bash
flutter test
```

```bash
cd rust && cargo test
```

Nenhum código nativo é construído por este package: ele não é plugin, não tem `cargokit`, não tem pasta de plataforma. Quem constrói Rust é o package de ponte do seu projeto.
