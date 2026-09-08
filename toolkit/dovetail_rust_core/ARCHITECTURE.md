# Arquitetura do dovetail_rust_core

Esse documento registra por que este package é pequeno e por que ele tem de continuar pequeno.

## A fronteira

```
app Flutter                 <- regra de negócio mora aqui
  └── package de ponte      <- fachada tipada do SEU núcleo Rust (DTO + repasse)
        └── dovetail_rust_core       <- este package: runtime, pump, sonda de plataforma
              └── crate Rust do seu projeto -> os crates do seu produto
```

A regra que sustenta a divisão: **este package não pode saber o nome de nenhuma entidade de aplicação**. Nem `Servidor`, nem `Assinatura`, nem `Túnel`. Se souber, deixou de ser camada de compatibilidade e virou o app de alguém — e nenhum segundo projeto consegue usá-lo.

Foi exatamente esse o erro na primeira versão: 106 linhas genéricas contra 1.327 de domínio, e quatro dependências de caminho para os crates de um produto específico. Um package assim tem nome de biblioteca e corpo de aplicação.

## Por que o runtime é um `OnceLock<Result<Runtime, String>>`

A forma óbvia estava errada e um teste pegou:

```rust
if let Some(r) = RUNTIME.get() { return Ok(r); }
let built = Builder::new_multi_thread().build()?;
Ok(RUNTIME.get_or_init(|| built))
```

Duas chamadas concorrentes constroem dois runtimes. Quem perde a corrida tem o seu `built` **largado dentro do `get_or_init`** — e largar um `Runtime` do tokio dentro de contexto assíncrono é panic: *"Cannot drop a runtime in a context where blocking is not allowed"*. Como o executor do `flutter_rust_bridge` é assíncrono, duas chamadas no boot derrubariam o processo.

Guardando o `Result` dentro do próprio `OnceLock`, o closure roda uma vez só, nada é construído em vão e nada é largado. O efeito colateral aceito: se a construção falhar, o erro fica em cache — e isso está certo, porque a falha é não conseguir criar threads, e repetir não conserta.

## Por que `pump` recebe closure em vez de `StreamSink`

`StreamSink` é tipo do `flutter_rust_bridge`. Aceitá-lo aqui traria o gerador de código como dependência deste package, e com ele a versão exata do frb — dois projetos em versões diferentes não poderiam compartilhar a camada. Recebendo `FnMut(T) -> bool`, o crate depende só de `tokio` e `tracing`, e quem tem o `StreamSink` é a fachada.

O contrato do retorno é `true` para continuar e `false` para parar. É o suficiente para o caso real: o sink morreu porque o Dart cancelou a inscrição.

## Por que `RustBridge` é instância e não estático

A primeira versão era `abstract final class` com estado estático e um `resetForTesting()`. Estado global exige porta de trás para teste, e porta de trás em código de produção é dívida. Uma instância guarda o próprio `Future` de inicialização: cada teste cria a sua, nada vaza entre testes, e não existe método que só serve para teste.

`ensureInitialized` limpa o `Future` guardado quando ele falha. Sem isso, um erro na primeira tentativa — biblioteca ausente, permissão — ficaria em cache e nenhuma tentativa posterior teria chance.

## Dependência local, não git

Os packages deste ecossistema entram por `path` no `pubspec.yaml` de quem consome, e por `path` no `Cargo.toml` do crate FFI. O destino é um monorepo com `crates/`, `packages/` e o app Flutter; com dependência local, essa mudança é mover diretório, não religar tipo de dependência.

## O que este package nunca vai ter

- `cargokit`, `podspec`, `CMakeLists` — quem constrói binário nativo é o package de ponte, porque é lá que mora o `cdylib` e o gerador.
- Dependência de `flutter_rust_bridge`, dos dois lados.
- Qualquer tipo com nome de domínio.
