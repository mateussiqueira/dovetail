use crate::requirement_blob::{parse, Clause, Comparison};
use crate::requirement_compile::compile_requirement;

const TEAM_FIELD: &[u8] = b"subject.OU";
const APP_STORE_OID: &[u8] = &[0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x06, 0x01, 0x09];

const PINNED: u8 = 1;
const ANCHORED: u8 = 2;
const NAMED: u8 = 4;
const TEAM: u8 = 8;
const APP_STORE: u8 = 16;

pub(crate) fn ensure_strong(requirement: &str) -> anyhow::Result<()> {
    let compiled = compile_requirement(requirement).map_err(|err| {
        anyhow::anyhow!("o requisito de assinatura nao compila: {requirement:?}: {err}")
    })?;
    anyhow::ensure!(
        is_strong(&parse(&compiled)?),
        "requisito de assinatura fraco demais para o canal privilegiado: {requirement:?}; \
         cada alternativa do or precisa de cdhash, ou de anchor apple generic, identifier e \
         certificate leaf[subject.OU] = \"<time>\"; always e ! sao recusados"
    );
    Ok(())
}

fn is_strong(compiled: &Clause) -> bool {
    !loosened(compiled)
        && alternatives(compiled)
            .into_iter()
            .all(admits_only_the_product)
}

fn admits_only_the_product(facts: u8) -> bool {
    let signed_by_the_product = facts & (TEAM | APP_STORE) != 0;
    let identified = facts & (ANCHORED | NAMED) == ANCHORED | NAMED;
    facts & PINNED != 0 || identified && signed_by_the_product
}

fn alternatives(clause: &Clause) -> Vec<u8> {
    let mut found = match clause {
        Clause::And(left, right) => {
            let right = alternatives(right);
            alternatives(left)
                .into_iter()
                .flat_map(|l| right.iter().map(move |r| l | r))
                .collect()
        }
        Clause::Or(left, right) => [alternatives(left), alternatives(right)].concat(),
        other => vec![fact(other)],
    };
    found.sort_unstable();
    found.dedup();
    found
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
        Clause::LeafExtension {
            oid,
            compared: Comparison::Exists,
        } if oid == APP_STORE_OID => APP_STORE,
        _ => 0,
    }
}

fn loosened(clause: &Clause) -> bool {
    match clause {
        Clause::True | Clause::Not(_) => true,
        Clause::And(left, right) | Clause::Or(left, right) => loosened(left) || loosened(right),
        _ => false,
    }
}
