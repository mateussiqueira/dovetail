#![cfg(target_os = "macos")]

use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Duration;

const LABEL: &str = "com.example.dovetail.xpcproof";

struct Proof {
    dir: PathBuf,
    plist: PathBuf,
}

impl Proof {
    fn start() -> Self {
        let dir = std::env::temp_dir().join(format!("dovetail-xpc-proof-{}", std::process::id()));
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
        let requirement = format!("cdhash H\"{}\"", cdhash(&app));
        let plist = dir.join(format!("{LABEL}.plist"));
        std::fs::write(
            &plist,
            property_list(&app, &requirement, &dir.join("served.log")),
        )
        .unwrap();
        launchctl(&["bootstrap", "system", plist.to_str().unwrap()]);
        std::thread::sleep(Duration::from_secs(1));
        Self { dir, plist }
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
        launchctl(&["bootout", &format!("system/{LABEL}")]);
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

fn property_list(app: &Path, requirement: &str, log: &Path) -> String {
    let strings = [
        app.to_str().unwrap(),
        "serve",
        LABEL,
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
         <key>Label</key><string>{LABEL}</string>\
         <key>MachServices</key><dict><key>{LABEL}</key><true/></dict>\
         <key>ProgramArguments</key><array>{strings}</array>\
         </dict></plist>\n"
    )
}

fn launchctl(args: &[&str]) {
    let _ = Command::new("launchctl").args(args).status();
}

#[test]
#[ignore = "needs root: bootstraps a LaunchDaemon; run with sudo, see the channel README"]
fn the_reviewer_escalation_is_refused_and_only_the_signed_app_is_heard() {
    let proof = Proof::start();
    proof.run("app", &["send", LABEL, "app-hello"]);
    proof.run("other", &["send", LABEL, "other-hello"]);
    let signed = proof.dir.join("app");
    proof.run("other", &["escalate", LABEL, signed.to_str().unwrap()]);
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
        "the connector was heard before its exec"
    );
    assert!(
        !served.contains("child-command"),
        "the forked child commanded the daemon"
    );
}
