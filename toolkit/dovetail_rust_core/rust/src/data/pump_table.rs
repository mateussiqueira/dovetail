use std::collections::HashMap;
use std::sync::{Arc, Mutex, MutexGuard};

use crate::domain::abortable_pump::AbortablePump;

/// A tabela de pumps por nome, e a politica de substituicao.
///
/// Generica sobre [AbortablePump] de proposito: a camada de dados nao
/// conhece o tokio. Quem amarra o tipo concreto e a fachada da crate.
pub struct PumpTable<P: AbortablePump> {
    entries: Arc<Mutex<HashMap<&'static str, P>>>,
}

/// Clonar a tabela e clonar o `Arc`, e nao os pumps — que nao sao
/// clonaveis nem deveriam ser. `#[derive(Clone)]` exigiria `P: Clone`
/// sobre um tipo que so e guardado atras de um Arc.
impl<P: AbortablePump> Clone for PumpTable<P> {
    fn clone(&self) -> Self {
        PumpTable {
            entries: Arc::clone(&self.entries),
        }
    }
}

impl<P: AbortablePump> Default for PumpTable<P> {
    fn default() -> Self {
        PumpTable::new()
    }
}

pub struct Replacement {
    pub name: &'static str,
    pub displaced_a_live_pump: bool,
}

impl<P: AbortablePump> PumpTable<P> {
    pub fn new() -> Self {
        PumpTable {
            entries: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// O mapa, mesmo depois de uma thread ter entrado em panico segurando o
    /// lock.
    ///
    /// Isto era `.expect("pump table poisoned")` em cinco lugares, e essa
    /// escolha custava caro do lado errado: esta tabela e alcancada por
    /// metodos SINCRONOS da ponte, que nao passam pelo runtime que captura
    /// panico. Um `expect` aqui atravessa o FFI e **aborta o processo** — a
    /// aplicacao hospedeira fecha, sem mensagem, sem log, sem tela de erro.
    ///
    /// O veneno avisa que o estado PODE estar inconsistente. Aqui o estado e
    /// um mapa de nome para tarefa de pump, e o pior caso concreto e uma
    /// entrada obsoleta: um pump que ja terminou continuar listado, o que
    /// `is_live` ja trata perguntando ao proprio pump. Trocar isso por
    /// derrubar a aplicacao inteira nao e prudencia, e desproporcao.
    fn entries(&self) -> MutexGuard<'_, HashMap<&'static str, P>> {
        self.entries
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    pub fn replace(&self, name: &'static str, pump: P) -> Replacement {
        let displaced = self.entries().insert(name, pump);

        let displaced_a_live_pump = displaced
            .as_ref()
            .map(|previous| !previous.is_finished())
            .unwrap_or(false);

        Replacement {
            name,
            displaced_a_live_pump,
        }
    }

    pub fn remove(&self, name: &'static str) -> bool {
        self.entries().remove(name).is_some()
    }

    pub fn len(&self) -> usize {
        self.entries().len()
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn is_live(&self, name: &'static str) -> bool {
        self.entries()
            .get(name)
            .map(|pump| !pump.is_finished())
            .unwrap_or(false)
    }

    pub fn clear(&self) {
        self.entries().clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicBool, Ordering};

    /// Um pump que nao roda nada: registra que foi solto e responde o que o
    /// teste mandar sobre estar terminado.
    ///
    /// Antes daqui existir, estes testes spawnavam tarefa tokio de verdade e
    /// mediam ticks com `sleep` — para provar a POLITICA de uma tabela. Um
    /// deles falhou no portao por carga na maquina (esta escrito no historico
    /// do arquivo), e o que ele queria dizer nunca dependeu de tempo. Que
    /// abortar interrompe o trabalho de verdade e provado onde a tarefa mora,
    /// em `infra::runtime_pump_task`.
    struct FakePump {
        finished: bool,
        dropped: Arc<AtomicBool>,
    }

    impl FakePump {
        fn live(dropped: Arc<AtomicBool>) -> Self {
            FakePump {
                finished: false,
                dropped,
            }
        }

        fn already_finished() -> Self {
            FakePump {
                finished: true,
                dropped: Arc::new(AtomicBool::new(false)),
            }
        }
    }

    impl AbortablePump for FakePump {
        fn abort(&self) {}

        fn is_finished(&self) -> bool {
            self.finished
        }
    }

    impl Drop for FakePump {
        fn drop(&mut self) {
            self.dropped.store(true, Ordering::SeqCst);
        }
    }

    fn live() -> FakePump {
        FakePump::live(Arc::new(AtomicBool::new(false)))
    }

    #[test]
    fn a_poisoned_table_keeps_answering_instead_of_killing_the_process() {
        let table: PumpTable<FakePump> = PumpTable::new();
        let borrowed = table.clone();

        // Envenena de verdade: uma thread entra em panico segurando o lock.
        // E o que acontece quando qualquer coisa dentro de um pump falha.
        let _ = std::thread::spawn(move || {
            let _guard = borrowed.entries.lock().expect("lock limpo aqui");
            panic!("um pump caiu segurando o lock");
        })
        .join();

        assert!(
            table.entries.is_poisoned(),
            "sem veneno o teste nao prova nada"
        );

        // A partir daqui, cada uma destas linhas era um abort do processo.
        // Esta tabela e alcancada por metodos SINCRONOS da ponte, que nao
        // passam pelo runtime que captura panico: um panico aqui atravessa o
        // FFI e fecha a aplicacao hospedeira sem mensagem nenhuma.
        assert_eq!(table.len(), 0);
        assert!(!table.remove("nao existe"));
        assert!(!table.is_live("nao existe"));

        let replacement = table.replace("state", live());
        assert_eq!(replacement.name, "state");
        assert!(table.is_live("state"), "a tabela envenenada ainda registra");

        table.clear();
        assert!(table.is_empty());
    }

    #[test]
    fn replacing_reports_that_it_displaced_a_live_pump() {
        let table: PumpTable<FakePump> = PumpTable::new();

        let first = table.replace("state", live());
        assert!(
            !first.displaced_a_live_pump,
            "the first subscription displaces nothing"
        );

        let second = table.replace("state", live());
        assert!(
            second.displaced_a_live_pump,
            "a second subscription to a live stream silently killed the first \
             one, and the caller could not tell"
        );
        assert_eq!(second.name, "state");
    }

    #[test]
    fn displacing_a_pump_that_already_finished_is_not_reported_as_live() {
        let table: PumpTable<FakePump> = PumpTable::new();
        table.replace("state", FakePump::already_finished());

        let second = table.replace("state", live());

        assert!(
            !second.displaced_a_live_pump,
            "um pump que ja terminou nao foi interrompido por ninguem, e dizer \
             que foi manda quem chama investigar o que nao aconteceu"
        );
    }

    #[test]
    fn the_displaced_pump_is_let_go() {
        // A tabela nao aborta a mao: ela solta o deslocado, e o Drop dele e
        // que interrompe o trabalho. Provar que ela SOLTA e o que cabe aqui;
        // que soltar interrompe esta provado em infra::runtime_pump_task.
        let table: PumpTable<FakePump> = PumpTable::new();
        let dropped = Arc::new(AtomicBool::new(false));

        table.replace("state", FakePump::live(dropped.clone()));
        assert!(!dropped.load(Ordering::SeqCst));

        table.replace("state", live());

        assert!(
            dropped.load(Ordering::SeqCst),
            "o pump deslocado ficou preso na memoria, e com ele o trabalho que \
             deveria ter parado"
        );
    }

    #[test]
    fn removing_lets_the_pump_go_and_empties_the_table() {
        let table: PumpTable<FakePump> = PumpTable::new();
        let dropped = Arc::new(AtomicBool::new(false));
        table.replace("state", FakePump::live(dropped.clone()));

        assert!(table.remove("state"));

        assert!(dropped.load(Ordering::SeqCst));
        assert!(table.is_empty());
        assert!(
            !table.remove("state"),
            "remover duas vezes tem de dizer que a segunda nao removeu nada"
        );
    }

    #[test]
    fn two_names_do_not_displace_each_other() {
        let table: PumpTable<FakePump> = PumpTable::new();

        table.replace("state", live());
        table.replace("traffic", live());

        assert_eq!(table.len(), 2);
        assert!(table.is_live("state"));
        assert!(table.is_live("traffic"));
    }

    #[test]
    fn clearing_lets_every_pump_go() {
        let table: PumpTable<FakePump> = PumpTable::new();
        let first = Arc::new(AtomicBool::new(false));
        let second = Arc::new(AtomicBool::new(false));
        table.replace("state", FakePump::live(first.clone()));
        table.replace("traffic", FakePump::live(second.clone()));

        table.clear();

        assert!(table.is_empty());
        assert!(first.load(Ordering::SeqCst));
        assert!(second.load(Ordering::SeqCst));
    }

    #[test]
    fn a_name_that_was_never_registered_is_not_live() {
        let table: PumpTable<FakePump> = PumpTable::new();

        assert!(!table.is_live("state"));
        assert_eq!(table.len(), 0);
        assert!(table.is_empty());
    }
}
