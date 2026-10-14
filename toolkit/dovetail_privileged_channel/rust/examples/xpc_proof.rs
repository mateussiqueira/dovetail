#[cfg(target_os = "macos")]
use std::time::Duration;

#[cfg(target_os = "macos")]
use dovetail_privileged_channel::{XpcConnection, XpcListener};

#[cfg(target_os = "macos")]
const SETTLE: Duration = Duration::from_millis(500);

fn main() {
    #[cfg(target_os = "macos")]
    run(std::env::args().skip(1).collect());
}

#[cfg(target_os = "macos")]
fn run(args: Vec<String>) {
    match args
        .iter()
        .map(String::as_str)
        .collect::<Vec<_>>()
        .as_slice()
    {
        ["serve", label, requirement, log] => serve(label, requirement, log),
        ["send", label, text] => send(label, text),
        ["escalate", label, signed] => escalate(label, signed),
        other => panic!("uso: serve|send|escalate, recebido {other:?}"),
    }
}

#[cfg(target_os = "macos")]
#[tokio::main]
async fn serve(label: &str, requirement: &str, log: &str) {
    let mut listener = XpcListener::mach_service(label, requirement).unwrap();
    while let Some(mut conn) = listener.accept().await {
        let log = log.to_string();
        tokio::spawn(async move {
            while let Some(message) = conn.recv().await {
                let line = format!("{}\n", String::from_utf8_lossy(&message));
                let mut file = std::fs::OpenOptions::new()
                    .create(true)
                    .append(true)
                    .open(&log)
                    .unwrap();
                std::io::Write::write_all(&mut file, line.as_bytes()).unwrap();
            }
        });
    }
}

#[cfg(target_os = "macos")]
fn send(label: &str, text: &str) {
    let conn = XpcConnection::mach_service(label).unwrap();
    conn.send(text.as_bytes());
    std::thread::sleep(SETTLE);
}

#[cfg(target_os = "macos")]
fn escalate(label: &str, signed: &str) {
    use std::os::unix::process::CommandExt;

    let conn = XpcConnection::mach_service(label).unwrap();
    conn.send(b"before-exec");
    std::thread::sleep(SETTLE);
    match unsafe { libc::fork() } {
        0 => {
            std::thread::sleep(SETTLE);
            conn.send(b"child-command");
            std::thread::sleep(SETTLE);
            unsafe { libc::_exit(0) };
        }
        child if child > 0 => {
            let err = std::process::Command::new(signed)
                .args(["send", label, "signed-after-exec"])
                .exec();
            panic!("exec do binario assinado falhou: {err}");
        }
        _ => panic!("fork falhou: {}", std::io::Error::last_os_error()),
    }
}
