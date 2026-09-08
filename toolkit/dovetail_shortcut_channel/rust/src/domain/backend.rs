/// Qual mecanismo de atalho global o host oferece — e o que ele permite.
/// O vocabulario e a regra moram aqui; QUEM olha a sessao para responder
/// mora em `infra::backend_probe`, porque isso e ler o ambiente.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[repr(i32)]
pub enum Backend {
    None = 0,
    Win32RegisterHotKey = 1,
    CarbonEventHotKey = 2,
    X11GrabKey = 3,
    WaylandPortal = 4,
}

impl Backend {
    pub fn registers(&self) -> bool {
        matches!(
            self,
            Backend::Win32RegisterHotKey | Backend::CarbonEventHotKey | Backend::X11GrabKey
        )
    }

    pub fn cannot_register(&self) -> String {
        match self {
            Backend::WaylandPortal => String::from(
                "a Wayland session grants a system-wide shortcut only through \
                 the desktop portal, where the compositor owns the chord. \
                 This channel does not speak that portal yet. Registering \
                 anyway would grab the key on XWayland, report success, and \
                 never fire.",
            ),
            _ => String::from(
                "no display and no compositor is reachable from this process, \
                 so there is no session to register a shortcut in. The \
                 backend accepts the registration regardless and reports \
                 success for a key that cannot arrive.",
            ),
        }
    }

    pub fn for_session(
        declared: Option<&str>,
        wayland_display: Option<&str>,
        x11_display: Option<&str>,
    ) -> Self {
        let declared = declared.unwrap_or_default().trim().to_ascii_lowercase();
        let wayland_socket = !wayland_display.unwrap_or_default().trim().is_empty();
        let x11_socket = !x11_display.unwrap_or_default().trim().is_empty();

        if declared == "x11" {
            return Backend::X11GrabKey;
        }
        if declared == "wayland" || wayland_socket {
            return Backend::WaylandPortal;
        }
        if x11_socket {
            return Backend::X11GrabKey;
        }
        Backend::None
    }
}

#[cfg(test)]
mod tests {
    use super::Backend;

    #[test]
    fn a_wayland_session_running_xwayland_is_not_an_x11_session() {
        assert_eq!(
            Backend::for_session(Some("wayland"), Some("wayland-0"), Some(":0")),
            Backend::WaylandPortal,
            "XWayland sets DISPLAY, and a key grabbed on it never sees what \
             the compositor delivers"
        );
    }

    #[test]
    fn a_compositor_started_from_a_tty_is_a_wayland_session() {
        assert_eq!(
            Backend::for_session(Some("tty"), Some("wayland-1"), Some(":0")),
            Backend::WaylandPortal,
            "sway and hyprland launched from a console leave XDG_SESSION_TYPE \
             at tty, and reading that as X11 grabs a key on XWayland that the \
             compositor never delivers"
        );
    }

    #[test]
    fn a_tty_compositor_without_xwayland_is_still_a_session() {
        assert_eq!(
            Backend::for_session(Some("tty"), Some("wayland-1"), None),
            Backend::WaylandPortal,
            "answering None here tells the user there is no session to bind \
             in, when there is one that needs the portal"
        );
    }

    #[test]
    fn a_wayland_socket_with_nothing_declared_is_still_wayland() {
        assert_eq!(
            Backend::for_session(None, Some("wayland-0"), Some(":0")),
            Backend::WaylandPortal
        );
    }

    #[test]
    fn a_declared_x11_session_wins_over_a_stale_wayland_socket() {
        assert_eq!(
            Backend::for_session(Some("x11"), Some("wayland-0"), Some(":0")),
            Backend::X11GrabKey
        );
    }

    #[test]
    fn an_x11_display_alone_is_an_x11_session() {
        assert_eq!(
            Backend::for_session(None, None, Some(":0")),
            Backend::X11GrabKey
        );
    }

    #[test]
    fn a_session_with_no_socket_at_all_has_no_backend() {
        assert_eq!(
            Backend::for_session(None, Some("  "), Some("")),
            Backend::None
        );
    }

    #[test]
    fn only_the_three_backends_that_grab_a_key_can_register() {
        assert!(Backend::Win32RegisterHotKey.registers());
        assert!(Backend::CarbonEventHotKey.registers());
        assert!(Backend::X11GrabKey.registers());
        assert!(
            !Backend::WaylandPortal.registers(),
            "global-hotkey registers on XWayland and reports success, and the \
             compositor delivers the key somewhere else"
        );
        assert!(
            !Backend::None.registers(),
            "measured in a container with no display at all: the manager \
             opens and the bind reports ok"
        );
    }

    #[test]
    fn a_backend_that_cannot_register_says_which_one_it_is() {
        assert!(Backend::WaylandPortal
            .cannot_register()
            .contains("desktop portal"));
        assert!(Backend::None.cannot_register().contains("no display"));
    }

    #[test]
    fn the_wire_codes_are_the_ones_dart_reads() {
        assert_eq!(Backend::None as i32, 0);
        assert_eq!(Backend::Win32RegisterHotKey as i32, 1);
        assert_eq!(Backend::CarbonEventHotKey as i32, 2);
        assert_eq!(Backend::X11GrabKey as i32, 3);
        assert_eq!(Backend::WaylandPortal as i32, 4);
    }
}
