#![cfg(target_os = "macos")]

use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Duration;

const LABEL: &str = "com.example.dovetail.xpcproof";
const CONTROL: &str = "com.example.dovetail.xpcproof.control";

struct Proof {
    label: &'static str,
    dir: PathBuf,
    plist: PathBuf,
}

impl Proof {
    fn start(label: &'static str, pinned: &str) -> Self {
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
        let requirement = format!("cdhash H\"{}\"", cdhash(&dir.join(pinned)));
        let plist = dir.join(format!("{label}.plist"));
        let log = dir.join("served.log");
        std::fs::write(&plist, property_list(label, &app, &requirement, &log)).unwrap();
        launchctl(&["bootstrap", "system", plist.to_str().unwrap()]);
        std::thread::sleep(Duration::from_secs(1));
        Self { label, dir, plist }
    }

    fn escalate(&self) {
        let signed = self.dir.join("app");
        self.run("other", &["escalate", self.label, signed.to_str().unwrap()]);
    }

    fn run(&self, program: &str, args: &[&str]) {
        let mut command = Command::new(self.dir.join(program));
        if let (Some(uid), Some(gid)) = (invoking("SUDO_UID"), invoking("SUDO_GID")) {
            command.uid(uid).gid(gid);
        }
        command.env("OBJC_DISABLE_INITIALIZE_FORK_SAFETY", "YES");
        let status = command.args(args).status().unwrap();
        assert!(status.success(), "{program} {args:?} terminou com {status}");
    }

    fn served(&self) -> String {
        std::thread::sleep(Duration::from_secs(2));
        std::fs::read_to_string(self.dir.join("served.log")).unwrap_or_default()
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

fn property_list(label: &str, app: &Path, requirement: &str, log: &Path) -> String {
    let strings = [
        app.to_str().unwrap(),
        "serve",
        label,
        requirement,
        log.to_str().unwrap(),
    ]
    .map(|s| {
        format!(
            "<string>{}</string>",
            s.replace('&', "&amp;").replace('"', "&quot;")
        )
    })
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
    let proof = Proof::start(LABEL, "app");
    proof.run("app", &["send", LABEL, "app-hello"]);
    proof.run("other", &["send", LABEL, "other-hello"]);
    proof.escalate();
    let served = proof.served();
    assert!(
        served.contains("app-hello"),
        "the signed app was not heard: {served:?}"
    );
    assert!(
        served.contains("signed-after-exec"),
        "the exec'd signed app was not heard: {served:?}"
    );
    assert!(
        !served.contains("other-hello"),
        "a process outside the requirement was heard"
    );
    assert!(
        !served.contains("before-exec"),
        "the connector's message, racing its exec, was judged as the signed app"
    );
    assert!(
        !served.contains("child-command"),
        "the forked child commanded the daemon"
    );
}

#[test]
#[ignore = "needs root: bootstraps a LaunchDaemon; run with sudo, see the channel README"]
fn the_shim_alone_control_hears_the_connector_it_admits_and_never_the_forked_child() {
    let proof = Proof::start(CONTROL, "other");
    proof.escalate();
    let served = proof.served();
    assert!(
        served.contains("before-exec"),
        "under a requirement that admits the connector its message must arrive: {served:?}"
    );
    assert!(
        !served.contains("child-command"),
        "the forked child was heard even though fork leaves it no send right to the service"
    );
}
