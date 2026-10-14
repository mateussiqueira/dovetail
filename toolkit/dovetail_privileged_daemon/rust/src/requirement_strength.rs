use crate::requirement_compile::compile_requirement;

pub(crate) fn ensure_strong(requirement: &str) -> anyhow::Result<()> {
    compile_requirement(requirement).map_err(|err| {
        anyhow::anyhow!("o requisito de assinatura nao compila: {requirement:?}: {err}")
    })?;
    let spaced = requirement.replace(['(', ')'], " ");
    let words: Vec<&str> = spaced.split_whitespace().collect();
    let text = words.join(" ");
    let weakening = ["always", "or"].iter().any(|word| words.contains(word)) || text.contains('!');
    let pinned = words.contains(&"cdhash");
    let team = text.contains("anchor apple generic")
        && words.contains(&"identifier")
        && text.contains("certificate leaf[subject.OU]");
    anyhow::ensure!(
        !weakening && (pinned || team),
        "requisito de assinatura fraco demais para o canal privilegiado: {requirement:?}; \
         use cdhash, ou anchor apple generic com identifier e certificate leaf[subject.OU]"
    );
    Ok(())
}
