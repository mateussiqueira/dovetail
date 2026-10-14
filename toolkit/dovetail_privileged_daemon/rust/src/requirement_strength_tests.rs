use crate::requirement_strength::ensure_strong;

const TEAM: &str = "anchor apple generic and identifier \"com.example.app\" \
                    and certificate leaf[subject.OU] = \"ABCDE12345\"";
const CDHASH: &str = "cdhash H\"0123456789abcdef0123456789abcdef01234567\"";

#[test]
fn always_is_refused() {
    assert!(ensure_strong("always").is_err());
}

#[test]
fn an_empty_requirement_is_refused() {
    assert!(ensure_strong("  ").is_err());
}

#[test]
fn an_identifier_alone_is_refused() {
    assert!(ensure_strong("identifier \"com.example.app\"").is_err());
}

#[test]
fn the_apple_anchor_alone_is_refused() {
    assert!(ensure_strong("anchor apple generic").is_err());
}

#[test]
fn an_anchor_and_identifier_without_the_team_is_refused() {
    let requirement = "anchor apple generic and identifier \"com.example.app\"";
    assert!(ensure_strong(requirement).is_err());
}

#[test]
fn a_strong_clause_widened_by_or_is_refused() {
    assert!(ensure_strong(&format!("{CDHASH} or always")).is_err());
}

#[test]
fn a_negated_clause_is_refused() {
    assert!(ensure_strong(&format!("!({CDHASH})")).is_err());
}

#[test]
fn a_pinned_cdhash_is_accepted() {
    assert!(ensure_strong(CDHASH).is_ok());
}

#[test]
fn the_team_identifier_and_anchor_together_are_accepted() {
    assert!(ensure_strong(TEAM).is_ok());
}

#[test]
fn the_team_clause_in_parentheses_is_accepted() {
    let requirement = format!("({TEAM})");
    assert!(ensure_strong(&requirement).is_ok());
}

#[test]
fn a_short_cdhash_that_does_not_compile_is_refused() {
    let refused = ensure_strong("cdhash H\"ab\"").unwrap_err();
    assert!(refused.to_string().contains("nao compila"), "{refused}");
}
