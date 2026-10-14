use crate::requirement_blob::{parse, Clause, Comparison};
use crate::requirement_compile::compile_requirement;

const TEAM_FIELD: &[u8] = b"subject.OU";

const PINNED: u8 = 1;
const ANCHORED: u8 = 2;
const NAMED: u8 = 4;
const TEAM: u8 = 8;

pub(crate) fn ensure_strong(requirement: &str) -> anyhow::Result<()> {
    let compiled = compile_requirement(requirement).map_err(|err| {
        anyhow::anyhow!("o requisito de assinatura nao compila: {requirement:?}: {err}")
    })?;
    anyhow::ensure!(
        is_strong(&parse(&compiled)?),
        "requisito de assinatura fraco demais para o canal privilegiado: {requirement:?}; \
         use cdhash, ou anchor apple generic, identifier e certificate leaf[subject.OU] = \"<time>\""
    );
    Ok(())
}

fn is_strong(compiled: &Clause) -> bool {
    admits_only_the_product(conjoined(compiled))
}

fn admits_only_the_product(facts: u8) -> bool {
    let signed_by_the_product = facts & TEAM != 0;
    let identified = facts & (ANCHORED | NAMED) == ANCHORED | NAMED;
    facts & PINNED != 0 || identified && signed_by_the_product
}

fn conjoined(clause: &Clause) -> u8 {
    match clause {
        Clause::And(left, right) => conjoined(left) | conjoined(right),
        other => fact(other),
    }
}

fn fact(clause: &Clause) -> u8 {
    match clause {
        Clause::CdHash(_) => PINNED,
        Clause::GenericAnchor => ANCHORED,
        Clause::Identifier(id) if !id.is_empty() => NAMED,
        Clause::LeafField {
            field,
            compared: Comparison::Equals(team),
        } if field == TEAM_FIELD && !team.is_empty() => TEAM,
        _ => 0,
    }
}
