# O mesmo ambiente do leg Linux do CI, sem runner hospedado.
#
# O portão roda em Ubuntu 24.04 x86_64 com Flutter e Rust pinados — os mesmos
# números do workflow. Este arquivo constrói esse ambiente num container, para
# a máquina do dono provar o leg Linux enquanto a conta não executa Actions.
#
# Por que o tarball entra por COPY em vez de ser baixado no build: a rede do
# buildkit desta máquina já falhou repetidamente contra storage.googleapis.com
# enquanto o host alcançava. Baixe uma vez no host e o build fica determinístico:
#
#   curl -fsSL -o flutter_linux.tar.xz \
#     "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
#
# Construir e rodar (o repo e os irmãos ficam montados em /work):
#
#   docker build --platform linux/amd64 -f tool/ci/gate-linux.Dockerfile -t dovetail-gate-linux .
#   docker run --platform linux/amd64 --name dovetail-gate-run \
#     -v <repo>:/work/dovetail \
#     -v <example-rust>:/work/example-rust:ro \
#     -v <example-design-system>:/work/example-design-system:ro \
#     dovetail-gate-linux bash -c \
#       "dart tool/verify.dart doctor && dart tool/verify.dart fast \
#        && dart tool/verify.dart test && dart tool/verify.dart rust --only toolkit \
#        && dart tool/verify.dart cross --only toolkit && dart tool/verify.dart readme"
#
# No Mac arm64 o container roda sob emulação qemu-x86_64: lento, mas é o mesmo
# binário x86_64 que o runner usaria. O diretório montado tem de morar sob o
# home do usuário — o Colima não compartilha /Volumes com a VM.
#
# Monte um volume para o pub cache e ele sobrevive aos runs:
#   -v dovetail-pub-cache:/root/.pub-cache
# Sem ele, o .dart_tool/package_config.json gravado no host aponta para um
# ~/.pub-cache do container anterior (morto), e o `fast` do run seguinte
# analisa contra caminhos que não existem — 77 erros que não são reais.

FROM ubuntu:24.04

ARG FLUTTER_VERSION=3.44.6
ARG RUST_VERSION=1.98.0

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/opt/flutter/bin:/root/.cargo/bin:${PATH}"

RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
      git curl ca-certificates unzip xz-utils zip file \
      clang cmake ninja-build pkg-config \
      libgtk-3-dev liblzma-dev libstdc++-12-dev \
      libayatana-appindicator3-dev \
      g++-mingw-w64-x86-64 minisign msitools osslsigncode rpm libxml2-utils \
      build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY flutter_linux.tar.xz /tmp/flutter.tar.xz
RUN mkdir -p /opt \
    && tar -xJf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz \
    && git config --global --add safe.directory '*' \
    && flutter config --no-analytics \
    && flutter precache --linux \
    && dart --version && flutter --version

RUN curl -fsSL https://sh.rustup.rs | sh -s -- -y --default-toolchain "${RUST_VERSION}" \
    && rustup target add x86_64-pc-windows-msvc x86_64-unknown-linux-gnu \
    && cargo --version

WORKDIR /work/dovetail
