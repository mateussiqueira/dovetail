**Português** · [English](SECURITY.md)

# Política de segurança

## Como relatar uma vulnerabilidade

Relate em particular, pelo relato privado de vulnerabilidades do GitHub: neste repositório, **Security → Report a vulnerability**, ou direto em <https://github.com/mateussiqueira/dovetail/security/advisories/new>. Não abra issue nem pull request público para isso.

Diga o que rodou, em qual sistema e commit, o que esperava e o que aconteceu. Uma prova de conceito ajuda mais que uma nota de gravidade. A correção é preparada no advisory privado e publicada com a versão que a carrega, com o seu crédito, salvo se você pedir o contrário.

## Escopo

No escopo: tudo o que está neste repositório — os pacotes e crates em `toolkit/`, o CLI e o canal do SDK, o `tool/sdk/install.sh` e o projeto que o `dovetail new` gera. As fronteiras e os furos já conhecidos estão em [docs/pt-BR/threat-model.md](docs/pt-BR/threat-model.md): um furo conhecido não é achado novo, mas um jeito de passar pelo que o contém é.

Fora do escopo: os apps feitos com o dovetail, que respondem por si; o Flutter, o Dart, o Rust e os pacotes de terceiros, que têm canais próprios (relate lá, e aqui também se o dovetail piora o caso); e quem já tem root ou administrador.

## Versões atendidas

O dovetail ainda não chegou à 1.0. Uma correção entra na `main` e na tag seguinte; tags antigas não recebem backport.
