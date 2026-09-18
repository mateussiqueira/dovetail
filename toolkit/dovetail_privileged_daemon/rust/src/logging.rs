static ARQUIVO_DE_LOG: std::sync::OnceLock<std::sync::Mutex<std::fs::File>> =
    std::sync::OnceLock::new();

struct EscritorDeLog;

impl std::io::Write for EscritorDeLog {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        if let Some(mutex) = ARQUIVO_DE_LOG.get() {
            if let Ok(mut arquivo) = mutex.lock() {
                let _ = arquivo.write_all(buf);
            }
        }
        let _ = std::io::Write::write_all(&mut std::io::stderr(), buf);
        Ok(buf.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        if let Some(mutex) = ARQUIVO_DE_LOG.get() {
            if let Ok(mut arquivo) = mutex.lock() {
                let _ = arquivo.flush();
            }
        }
        Ok(())
    }
}

fn abrir_arquivo_de_log(dir: &str, nome: &str) -> Option<std::fs::File> {
    let dir = std::path::Path::new(dir);
    std::fs::create_dir_all(dir).ok()?;
    let caminho = dir.join(nome);

    if let Ok(meta) = std::fs::metadata(&caminho) {
        if meta.len() > 4 * 1024 * 1024 {
            let _ = std::fs::rename(&caminho, dir.join(format!("{nome}.old")));
        }
    }

    std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&caminho)
        .ok()
}

pub(crate) fn init(log_dir: &str, filter: &str, file: Option<&str>) {
    use tracing_subscriber::EnvFilter;

    if let Some(nome) = file {
        if let Some(arquivo) = abrir_arquivo_de_log(log_dir, nome) {
            let _ = ARQUIVO_DE_LOG.set(std::sync::Mutex::new(arquivo));
        }
    }

    let filtro = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new(filter));

    let _ = tracing_subscriber::fmt()
        .with_env_filter(filtro)
        .with_ansi(false)
        .with_writer(|| EscritorDeLog)
        .try_init();
}
