#!/usr/bin/env bash
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
ORIGEM="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
T="$(mktemp -d)" || exit 1
trap 'rm -rf "$T"' EXIT
R="$T/repo"
FALHAS=0
CASOS=0
LINGUAS=()
command -v gofmt > /dev/null 2>&1 && LINGUAS+=(go)
command -v dart > /dev/null 2>&1 && LINGUAS+=(dart)
command -v rustfmt > /dev/null 2>&1 && LINGUAS+=(rs)
X="${LINGUAS[0]:-}"

sha() {
  if command -v sha256sum > /dev/null 2>&1; then sha256sum
  elif command -v shasum > /dev/null 2>&1; then shasum -a 256
  else openssl dgst -sha256 -r; fi | cut -c1-64
}

escreve() { mkdir -p "$R/$(dirname "$1")" && printf '%b' "$2" > "$R/$1"; }

repete() {
  local i=0
  while [ "$i" -lt "$2" ]; do printf '%s' "$1"; i=$((i + 1)); done
}

codigo() {
  local i=1
  [ "$1" = go ] && { printf 'package x\n\n'; i=3; }
  while [ "$i" -le "$2" ]; do
    case "$1" in
      go) printf 'var v%d = %d\n' "$i" "$i" ;;
      dart) printf 'int v%d = %d;\n' "$i" "$i" ;;
      rs) printf 'pub const V%d: i32 = %d;\n' "$i" "$i" ;;
    esac
    i=$((i + 1))
  done
}

relata() {
  CASOS=$((CASOS + 1))
  if [ "$2" = 0 ]; then printf 'ok     %s\n' "$1"; else printf 'FALHOU %s: %s\n' "$1" "$3" | sed '2,$s/^/    /'; FALHAS=$((FALHAS + 1)); fi
  git -C "$R" reset -q --hard base && git -C "$R" clean -qfdx
}

caso() {
  local espera="$2" trecho="${3:-}" saida rc ok=1
  git -C "$R" add -A
  saida="$(cd "$R" && git commit -q -m caso 2>&1)"
  rc=$?
  if { [ "$espera" = recusa ] && [ "$rc" -ne 0 ]; } || { [ "$espera" = passa ] && [ "$rc" -eq 0 ]; }; then
    { [ -z "$trecho" ] || printf '%s\n' "$saida" | grep -qF -- "$trecho"; } && ok=0
  fi
  relata "$1" "$ok" "esperava $espera com \"$trecho\"; saída $rc"$'\n'"$saida"
}

confere() {
  local saida rc ok=1
  saida="$(cd "$2" && bash scripts/checks/pre_commit.sh --conferir 2>&1)"
  rc=$?
  { [ "$3" = passa ] && [ "$rc" -eq 0 ]; } || { [ "$3" = recusa ] && [ "$rc" -ne 0 ] && printf '%s\n' "$saida" | grep -qF -- "${4:-}"; } && ok=0
  relata "$1" "$ok" "saída $rc"$'\n'"$saida"
}

prepara() {
  local l
  git init -q "$R" || exit 1
  git -C "$R" config user.name autoteste
  git -C "$R" config user.email autoteste@example.invalid
  git -C "$R" config core.hooksPath .githooks
  git -C "$R" config commit.gpgsign false
  mkdir -p "$R/.githooks" "$R/scripts/checks"
  cp "$ORIGEM/.githooks/pre-commit" "$R/.githooks/pre-commit" || exit 1
  cp "$ORIGEM/scripts/checks/pre_commit.sh" "$R/scripts/checks/pre_commit.sh" || exit 1
  chmod +x "$R/.githooks/pre-commit"
  PALAVRA="zorbax""trim"
  escreve scripts/checks/forbidden_words.sha256 "$(printf '%s' "$PALAVRA" | sha) sub ${#PALAVRA}\n"
  for l in go dart rs; do
    if [ "$l" = "$X" ]; then printf 'linguagem %s 150 src/\n' "$l"; else printf 'linguagem %s 150\n' "$l"; fi
  done > "$R/scripts/checks/pre_commit.conf"
  printf 'excecao %s isentos.list\nteto %s tetos.list\nignorar modelos/\n' "$X" "$X" >> "$R/scripts/checks/pre_commit.conf"
  printf 'comentarios bash gate/comentarios.sh\ncomentarios bash gate/inexistente.sh\n' >> "$R/scripts/checks/pre_commit.conf"
  escreve isentos.list "isento_grande\n"
  escreve tetos.list "src/teto.$X 160\n"
  escreve gate/comentarios.sh "git diff --cached -U0 | grep -q '^+.*MARCA-DE''-COMENTARIO' && { echo 'MARCA-DE''-COMENTARIO achado'; exit 1; }\nexit 0\n"
  escreve rs/Cargo.toml '[package]\nname = "rs"\nedition = "2021"\n'
  escreve antigo/Cargo.toml '[package]\nname = "antigo"\nedition = "2015"\n'
  git -C "$R" add -A
  (cd "$R" && git commit -q -m base > "$T/base" 2>&1) || { sed "s/^/    /" "$T/base"; echo "FALHOU o commit base, limpo, foi recusado"; exit 1; }
  git -C "$R" tag base
}

prepara
R36="$(repete A1b2C3d4 5 | cut -c1-36)"
HEX32="$(repete 0123456789abcdef 2)"

escreve .env "X=1\n"
caso "nome sensível" recusa "arquivo sensível: .env"
escreve .env.example "X=\n"
caso "nome sensível isento por ser modelo" passa
escreve config/secrets.txt "x\n"
caso "palavra sensível em nome que não é fonte" recusa "arquivo sensível: config/secrets.txt"
escreve docs/token.md "x\n"
caso "palavra sensível em nome de fonte" passa
escreve chave.txt '-----BEGIN'' RSA PRIVATE KEY-----\n'
caso "segredo: chave privada" recusa "pre-commit: possível segredo em chave.txt:1"
escreve conf.txt "a = 1\ntoken = \"gh""p_$R36\"\n"
caso "segredo: token do GitHub" recusa "pre-commit: possível segredo em conf.txt:2"
escreve dsn.txt "dsn = \"https://$HEX32@o1.ingest.sentry.io/7\"\n"
caso "segredo: DSN com chave de 32 hex" recusa "pre-commit: possível segredo em dsn.txt:1"
escreve fixtures.txt "id = \"AKIA""IOSFODNN7EXAMPLE\"\na = \"https://$(repete 0 32)@example.invalid/42\"\nb = \"http://$HEX32@127.0.0.1:8000/7\"\nPrivateKey = $(printf 'fake-private-key-para-teste==' | base64)\n"
caso "fixtures de teste sem falso positivo" passa
if command -v gitleaks > /dev/null 2>&1; then
  escreve shop.txt "k = \"shp""at_$(repete 0f1e2d3c 4)\"\n"
  caso "segredo que só o gitleaks pega" recusa "pre-commit: gitleaks: possível segredo em shop.txt:1"
fi
for l in ${LINGUAS[@]+"${LINGUAS[@]}"}; do
  case "$l" in
    go) escreve a.go "package x\nfunc  F() {}\n"; caso "formato Go" recusa "formato: a.go fora do gofmt" ;;
    dart) escreve a.dart "void f( ) {}\n"; caso "formato Dart" recusa "formato: a.dart fora do dart format" ;;
    rs) escreve rs/src/lib.rs "fn f( ) {}\n"; caso "formato Rust" recusa "formato: rs/src/lib.rs fora do rustfmt"
      escreve antigo/src/lib.rs "pub async fn f() {}\n"; caso "edição do Cargo.toml mais próximo" recusa "formato: antigo/src/lib.rs fora do rustfmt" ;;
  esac
done
if [ -n "$X" ]; then
  escreve "src/gerado.$X" "// Code generated by autoteste. DO NOT EDIT.\n$(codigo "$X" 300)  \n"
  caso "arquivo gerado fica fora de formato e tamanho" passa
  escreve "modelos/x.$X" "nao compila (\n"
  caso "prefixo ignorado fica fora de formato e tamanho" passa
  codigo "$X" 151 > "$T/151"
  escreve "src/grande.$X" "$(cat "$T/151")\n"
  caso "tamanho acima do limite" recusa "tamanho: src/grande.$X tem 151 linhas (limite 150)"
  escreve "fora/grande.$X" "$(cat "$T/151")\n"
  caso "tamanho fora do prefixo da regra" passa
  escreve "src/isento_grande.$X" "$(cat "$T/151")\n"
  caso "tamanho na lista de exceção" passa
  escreve "src/teto.$X" "$(codigo "$X" 160)\n"
  caso "tamanho dentro do teto herdado" passa
  escreve "src/teto.$X" "$(codigo "$X" 161)\n"
  caso "tamanho acima do teto herdado" recusa "tamanho: src/teto.$X tem 161 linhas (limite 160)"
fi
escreve notas.txt "MARCA-DE""-COMENTARIO aqui\n"
caso "portão de comentários do repositório" recusa "comentários: 'bash gate/comentarios.sh' reprovou"
escreve notas.txt "texto\n"
caso "portão de comentários ausente é pulado" passa "gate/inexistente.sh ainda não existe"
escreve notas.md "o autor Zorbax""trim\nlinha limpa\nveja rzorbax""trimdev\n"
caso "palavra proibida, por hash, inteira e dentro de outra" recusa "pre-commit: 2 problema(s)"
escreve notas.md "o autor Fulano\n"
for l in ${LINGUAS[@]+"${LINGUAS[@]}"}; do
  case "$l" in
    go) escreve limpo.go "package x\n\nfunc F() {}\n" ;;
    dart) escreve limpo.dart "void f() {}\n" ;;
    rs) escreve rs/src/lib.rs "pub async fn f() {}\n" ;;
  esac
done
caso "commit limpo" passa "pre-commit: ok"
rm "$R/scripts/checks/pre_commit.sh"
escreve notas.md "x\n"
caso "envoltório sem o motor na árvore" passa "ausente nesta árvore"
printf 'linguagem cobol 10\n' >> "$R/scripts/checks/pre_commit.conf"
confere "configuração inválida é recusada" "$R" recusa "use 'linguagem go|dart|rs"
printf 'nao-e-hash sub 9\n' >> "$R/scripts/checks/forbidden_words.sha256"
confere "lista de palavras inválida é recusada" "$R" recusa "toda linha é '<sha256> sub <tamanho>'"
confere "configuração real do repositório" "$ORIGEM" passa
echo "autoteste do pre-commit: $CASOS casos, $FALHAS falha(s); linguagens com formatador: ${LINGUAS[*]:-nenhuma}"
[ "$FALHAS" -eq 0 ]
