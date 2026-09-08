# {{name}}

> Gerado por `dovetail bridge init` a partir do template do SDK. O mecanismo
> que este package reproduz é o do `product/desktop_core_bridge`, o fixture —
> o que o template deliberadamente não traz é o conteúdo do produto.

O canal tipado entre o Flutter e o núcleo Rust de um produto desktop: cada
função em `rust/src/api/` é um repasse, cada tipo é um espelho, e o package
**não decide nada** — regra de negócio aqui seria acoplar o app a um package.

## A fronteira

```
app Flutter desktop        <- a regra de negócio mora aqui, e só aqui
  └── {{name}}             <- este package: repasse + espelho
        └── dovetail_rust_core      <- camada de compatibilidade Dart<->Rust
              └── o crate do produto ({{core_crate_name}}, o --core do init)
```

## O laço

1. Escreva os repasses em `rust/src/api/` — um módulo por área, cada função
   chamando o crate por baixo do `support::run`.
2. Rode o codegen:

```bash
flutter_rust_bridge_codegen generate
```

Ele gera `rust/src/frb_generated.rs` e `lib/src/rust/`. Sem ele, o `cargo
check` falha nomeando o módulo ausente — é o laço trabalhando, não defeito.

3. Confira que o Rust compila:

```bash
cd rust && cargo check
```

4. Construa o XCFramework do SPM (o macOS resolve o plugin via Swift Package
   Manager desde o Flutter 3.44, e o `Package.swift` aponta para ele):

```bash
tool/build_xcframework.sh
```

O `.xcframework` não é versionado — adicione `*.xcframework` ao `.gitignore`
do seu repo e rode o script depois de cada mudança em Rust. Quem prefere o
CocoaPods ignora o passo: o podspec/cargokit continua de pé.

5. O portão de forma, que cobra cada método público do núcleo:

```bash
flutter test test/core_coverage_test.dart
```

Ele lê o `handle.rs` do crate (o caminho que o `bridge init` gravou) e as
chamadas em `rust/src/api/`, e recusa quando o núcleo cresceu um método que
nenhum repasse expõe. Um método que você decide não expor entra na
`_deliberatelyNotExposed` do teste — com o motivo escrito, senão o teste
recusa o silêncio.

## O que o template não traz, de propósito

- `rust/src/api/*` — o conteúdo é do produto; o template entrega o diretório
  vazio e o padrão.
- `lib/src/rust/*` — gerado, nunca escrito à mão.
- O `example/` — o app mínimo que exercita a ponte por FFI de verdade.
- Os outros crates do produto no `Cargo.toml` — só o `--core` entra; se o seu
  `api` usa mais crates irmãos, declare-os como o fixture faz.

Os caminhos gravados (o crate, o `dovetail_rust_core`) são absolutos: o gerado pode
morar em qualquer lugar, e é de quem gerou.
