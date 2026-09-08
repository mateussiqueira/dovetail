/// O que a tabela precisa saber de um pump: se ele ja terminou, e como
/// pedir que pare. Nada de runtime, nada de tokio.
///
/// Existe porque a tabela guardava a tarefa CONCRETA, e com isso um teste
/// da tabela — que e uma estrutura de dados com uma politica de
/// substituicao — precisava de um runtime tokio de pe para existir. O
/// contrato aqui deixa a politica ser provada com um duplo, e a tarefa de
/// verdade continua sendo provada onde ela mora.
pub trait AbortablePump {
    fn abort(&self);

    fn is_finished(&self) -> bool;
}
