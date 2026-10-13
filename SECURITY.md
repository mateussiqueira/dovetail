**English** · [Português](SECURITY.pt-BR.md)

# Security policy

## Reporting a vulnerability

Report it privately, through GitHub's private vulnerability reporting: on this repository, **Security → Report a vulnerability**, or straight at <https://github.com/mateussiqueira/dovetail/security/advisories/new>. Please do not open a public issue or pull request for it.

Say what you ran, on which system and commit, what you expected and what happened. A proof of concept helps more than a severity score. The fix is prepared in the private advisory and published with the release that carries it, crediting you unless you ask otherwise.

## Scope

In scope: everything in this repository — the packages and crates under `toolkit/`, the CLI and its SDK channel, `tool/sdk/install.sh`, and the project that `dovetail new` generates. The boundaries and the gaps already known are in [docs/threat-model.md](docs/threat-model.md): a known gap is not a new finding, but a way past what contains it is.

Out of scope: the apps built with dovetail, which their authors answer for; Flutter, Dart, Rust and third-party packages, which have their own channels (report there, and here too if dovetail makes it worse); and an attacker who already has root or administrator rights.

## Supported versions

dovetail is before 1.0. A fix lands on `main` and in the next tag; older tags get no backport.
