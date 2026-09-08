.PHONY: quality quality-flutter quality-rust codegen tests run hooks build

quality: quality-flutter quality-rust

quality-flutter:
	bash scripts/checks/flutter/run_all.sh

quality-rust:
	bash scripts/checks/rust/run_all.sh

codegen:
	cd core_bridge && flutter_rust_bridge_codegen generate && cd rust && cargo check

# Os DOIS pacotes, e nao so o app.
#
# O scaffold escreve `core_bridge/test/core_coverage_test.dart` — a rede exata
# contra a ponte atrasada: um metodo novo no nucleo Rust sem regenerar o Dart.
# Medido: com um metodo a mais em `core/src/handle.rs`, `make codegen` sai 0,
# `flutter test` do app passa 6/6, o gate rust sai 0, e o metodo nao existe no
# Dart. So esse teste pega — e nenhum alvo o invocava.
#
# O `pub get` esta na mesma linha porque `dovetail new` nunca resolve o bridge:
# sem ele a primeira invocacao pagaria uma resolucao de 32 pacotes dentro de um
# passo cuja mensagem de falha nao a mencionaria.
tests:
	flutter test
	cd core_bridge && flutter pub get && flutter test

# Sem `quality` como pre-requisito: o run_app.sh ja roda as duas suites de
# checks por dentro (run_gate), entao `make run` as executava DUAS vezes —
# 1,66s + 0,36s repetidos a cada subida do app. A decisao de o run_app.sh
# rodar o gate e dele, com o ESCOPO_TUDO do dia zero explicado la; aqui so
# se deixa de pagar em dobro.
run:
	./run_app.sh

hooks:
	git config core.hooksPath .githooks

build:
	flutter build macos
