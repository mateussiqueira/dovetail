#[cfg(any(test, all(unix, not(target_os = "macos"))))]
use crate::handshake::PeerCheck;

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PeerPolicy {
    uids: Vec<u32>,
    gids: Vec<u32>,
    code: Option<String>,
}

impl PeerPolicy {
    pub fn allow_uid(mut self, uid: u32) -> Self {
        self.uids.push(uid);
        self
    }

    pub fn allow_gid(mut self, gid: u32) -> Self {
        self.gids.push(gid);
        self
    }

    pub fn require_code(mut self, requirement: impl Into<String>) -> Self {
        self.code = Some(requirement.into());
        self
    }

    pub fn code_requirement(&self) -> Option<&str> {
        self.code.as_deref()
    }

    pub fn admits(&self, uid: u32, gid: u32) -> bool {
        self.uids.contains(&uid) || self.gids.contains(&gid)
    }
}

#[cfg(any(test, all(unix, not(target_os = "macos"))))]
pub(crate) struct PeerCred {
    pub(crate) pid: i32,
    pub(crate) uid: u32,
    pub(crate) gid: u32,
}

#[cfg(any(test, all(unix, not(target_os = "macos"))))]
pub(crate) fn judge(policy: Option<&PeerPolicy>, peer: PeerCred) -> anyhow::Result<PeerCheck> {
    let subject = format!("pid={} uid={} gid={}", peer.pid, peer.uid, peer.gid);
    let Some(policy) = policy else {
        anyhow::bail!(
            "politica de peer ausente, {subject} recusado: no Linux o canal recusa todo \
             peer ate o produto declarar quem pode falar com \
             Endpoint::with_peer_policy(PeerPolicy::default().allow_uid(..))"
        );
    };
    anyhow::ensure!(
        policy.admits(peer.uid, peer.gid),
        "{subject} fora da politica de peer"
    );
    Ok(PeerCheck {
        method: "peercred+policy".to_string(),
        subject,
    })
}

#[cfg(any(test, all(unix, not(target_os = "macos"))))]
pub(crate) struct SocketModes {
    pub(crate) directory: u32,
    pub(crate) socket: u32,
}

#[cfg(any(test, all(unix, not(target_os = "macos"))))]
pub(crate) fn socket_modes(policy: Option<&PeerPolicy>) -> SocketModes {
    match policy {
        Some(_) => SocketModes {
            directory: 0o755,
            socket: 0o666,
        },
        None => SocketModes {
            directory: 0o700,
            socket: 0o600,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn the_user() -> PeerCred {
        PeerCred {
            pid: 4242,
            uid: 1000,
            gid: 1000,
        }
    }

    #[test]
    fn without_a_policy_even_root_is_refused_and_told_what_to_declare() {
        let root = PeerCred {
            pid: 1,
            uid: 0,
            gid: 0,
        };
        let refusal = judge(None, root).unwrap_err().to_string();
        assert!(refusal.starts_with("politica de peer ausente"), "{refusal}");
        assert!(refusal.contains("Endpoint::with_peer_policy"), "{refusal}");
    }

    #[test]
    fn a_policy_that_names_the_uid_admits_the_peer() {
        let policy = PeerPolicy::default().allow_uid(1000);
        let peer = judge(Some(&policy), the_user()).unwrap();
        assert_eq!(peer.method, "peercred+policy");
        assert_eq!(peer.subject, "pid=4242 uid=1000 gid=1000");
    }

    #[test]
    fn a_policy_that_names_neither_the_uid_nor_the_gid_refuses_the_peer() {
        let policy = PeerPolicy::default().allow_uid(0).allow_gid(27);
        let refusal = judge(Some(&policy), the_user()).unwrap_err().to_string();
        assert_eq!(
            refusal,
            "pid=4242 uid=1000 gid=1000 fora da politica de peer"
        );
    }

    #[test]
    fn the_gid_alone_admits_and_is_never_read_as_a_uid() {
        let policy = PeerPolicy::default().allow_gid(1000);
        assert!(policy.admits(4321, 1000));
        assert!(!policy.admits(1000, 4321));
    }

    #[test]
    fn without_a_policy_only_the_owner_reaches_the_socket() {
        let modes = socket_modes(None);
        assert_eq!(modes.directory, 0o700);
        assert_eq!(modes.socket, 0o600);
    }

    #[test]
    fn with_a_policy_every_local_user_reaches_the_socket_and_the_policy_decides() {
        let policy = PeerPolicy::default().allow_gid(1000);
        let modes = socket_modes(Some(&policy));
        assert_eq!(modes.directory, 0o755);
        assert_eq!(modes.socket, 0o666);
    }
}
