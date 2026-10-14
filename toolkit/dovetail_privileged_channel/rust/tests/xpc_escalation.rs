#![cfg(target_os = "macos")]

use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::time::Duration;

const LABEL: &str = "com.example.dovetail.xpcproof";
const CONTROL: &str = "com.example.dovetail.xpcproof.control";
const HELD: &str = "com.example.dovetail.xpcproof.held";

struct Proof {
    label: &'static str,
    dir: PathBuf,
    plist: PathBuf,
    senders: Vec<Child>,
}

impl Proof {
    fn start(label: &'static str, pinned: &[&str], held: bool) -> Self {
        let dir = std::env::temp_dir().join(format!("{label}-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let example = std::env::current_exe()
            .unwrap()
            .parent()
            .unwrap()
            .parent()
            .unwrap()
            .join("examples/xpc_proof");
        assert!(
            example.exists(),
            "build it first: cargo build --example xpc_proof"
        );
        let app = signed_copy(&example, &dir.join("app"), "com.example.dovetail.app");
        signed_copy(&example, &dir.join("other"), "com.example.dovetail.other");
        let requirement = pinned
            .iter()
            .map(|program| format!("cdhash H\"{}\"", cdhash(&dir.join(program))))
            .collect::<Vec<_>>()
            .join(" or ");
        let plist = dir.join(format!("{label}.plist"));
        let log = dir.join("served.log");
        let signal = held.then(|| dir.join("exec-done"));
        let listing = property_list(label, &app, &requirement, &log, signal.as_deref());
        std::fs::write(&plist, listing).unwrap();
        launchctl(&["bootstrap", "system", plist.to_str().unwrap()]);
        std::thread::sleep(Duration::from_secs(1));
        Self {
            label,
            dir,
            plist,
            senders: Vec::new(),
        }
    }

    fn send(&mut self, program: &str, text: &str) {
        let hold = self.dir.join("release");
        self.spawn(program, &["send", self.label, text, hold.to_str().unwrap()]);
    }

    fn escalate(&mut self) {
        let signed = self.dir.join("app");
        let hold = self.dir.join("release");
        let args = [
            "escalate",
            self.label,
            signed.to_str().unwrap(),
            hold.to_str().unwrap(),
        ];
        self.spawn("other", &args);
    }

    fn release_daemon(&self) {
        std::thread::sleep(Duration::from_secs(2));
        std::fs::write(self.dir.join("exec-done"), b"").unwrap();
    }

    fn spawn(&mut self, program: &str, args: &[&str]) {
        let mut command = Command::new(self.dir.join(program));
        if let (Some(uid), Some(gid)) = (invoking("SUDO_UID"), invoking("SUDO_GID")) {
            command.uid(uid).gid(gid);
        }
        command.env("OBJC_DISABLE_INITIALIZE_FORK_SAFETY", "YES");
        self.senders.push(command.args(args).spawn().unwrap());
    }

    fn served(&mut self) -> String {
        std::thread::sleep(Duration::from_secs(2));
        let served = std::fs::read_to_string(self.dir.join("served.log")).unwrap_or_default();
        std::fs::write(self.dir.join("release"), b"").unwrap();
        for mut sender in self.senders.drain(..) {
            let status = sender.wait().unwrap();
            assert!(status.success(), "a sender ended with {status}");
        }
        served
    }
}

impl Drop for Proof {
    fn drop(&mut self) {
        launchctl(&["bootout", &format!("system/{}", self.label)]);
        let _ = std::fs::remove_file(&self.plist);
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

fn invoking(variable: &str) -> Option<u32> {
    std::env::var(variable).ok()?.parse().ok()
}

fn signed_copy(from: &Path, to: &Path, identifier: &str) -> PathBuf {
    std::fs::copy(from, to).unwrap();
    let signed = Command::new("codesign")
        .args(["-f", "-s", "-", "-i", identifier])
        .arg(to)
        .status()
        .unwrap();
    assert!(signed.success(), "codesign {identifier} falhou");
    to.to_path_buf()
}

fn cdhash(program: &Path) -> String {
    let out = Command::new("codesign")
        .arg("-dvvv")
        .arg(program)
        .output()
        .unwrap();
    let text = String::from_utf8_lossy(&out.stderr).to_string();
    let line = text.lines().find(|l| l.starts_with("CDHash=")).unwrap();
    line.trim_start_matches("CDHash=").to_string()
}

fn property_list(
    label: &str,
    app: &Path,
    requirement: &str,
    log: &Path,
    signal: Option<&Path>,
) -> String {
    let mode = if signal.is_some() {
        "serve-after"
    } else {
        "serve"
    };
    let strings = [
        app.to_str(),
        Some(mode),
        Some(label),
        Some(requirement),
        log.to_str(),
        signal.and_then(Path::to_str),
    ]
    .into_iter()
    .flatten()
    .map(|s| {
        format!(
            "<string>{}</string>",
            s.replace('&', "&amp;").replace('"', "&quot;")
        )
    })
    .collect::<Vec<_>>()
    .join("");
    format!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict>\
         <key>Label</key><string>{label}</string>\
         <key>MachServices</key><dict><key>{label}</key><true/></dict>\
         <key>ProgramArguments</key><array>{strings}</array>\
         </dict></plist>\n"
    )
}

fn launchctl(args: &[&str]) {
    let _ = Command::new("launchctl").args(args).status();
}

#[test]
#[ignore = "needs root: bootstraps a LaunchDaemon; run with sudo, see the channel README"]
fn the_shim_alone_refuses_the_reviewer_escalation_and_hears_only_the_signed_app() {
    let mut proof = Proof::start(LABEL, &["app"], false);
    proof.send("app", "app-hello");
    proof.send("other", "other-hello");
    proof.escalate();
    let served = proof.served();
    assert!(
        served.contains("app-hello"),
        "the live signed app was not heard: {served:?}"
    );
    assert!(
        served.contains("signed-after-exec"),
        "the live exec'd signed app was not heard: {served:?}"
    );
    assert!(
        !served.contains("other-hello"),
        "a live process outside the requirement was heard"
    );
    assert!(
        !served.contains("before-exec"),
        "the connector's message was taken for the signed app it exec'd"
    );
    assert!(
        !served.contains("child-command"),
        "the forked child commanded the daemon"
    );
}

#[test]
#[ignore = "needs root: bootstraps a LaunchDaemon; run with sudo, see the channel README"]
fn the_shim_alone_control_hears_a_live_admitted_sender_and_never_the_forked_child() {
    let mut proof = Proof::start(CONTROL, &["other"], false);
    proof.send("other", "other-hello");
    proof.escalate();
    let served = proof.served();
    assert!(
        served.contains("other-hello"),
        "a live sender the requirement admits must be heard: {served:?}"
    );
    assert!(
        !served.contains("signed-after-exec"),
        "the app was heard under a requirement that pins the other"
    );
    assert!(
        !served.contains("child-command"),
        "the forked child was heard even though fork leaves it no send right to the service"
    );
}

#[test]
#[ignore = "needs root: bootstraps a LaunchDaemon; run with sudo, see the channel README"]
fn a_message_judged_after_its_sender_exec_never_arrives_even_when_both_images_are_admitted() {
    let mut proof = Proof::start(HELD, &["other", "app"], true);
    proof.send("other", "other-alive");
    proof.escalate();
    proof.release_daemon();
    let served = proof.served();
    assert!(
        served.contains("other-alive"),
        "a live sender of the connector's image was not heard: {served:?}"
    );
    assert!(
        served.contains("signed-after-exec"),
        "the live exec'd app was not heard once the daemon checked in: {served:?}"
    );
    assert!(
        !served.contains("before-exec"),
        "a message whose sender exec'd before the daemon judged it was heard"
    );
    assert!(
        !served.contains("child-command"),
        "the forked child commanded the daemon"
    );
}
