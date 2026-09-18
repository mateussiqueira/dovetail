pub fn redact_route(url: &str) -> String {
    let (base, _query) = url.split_once('?').unwrap_or((url, ""));

    let (prefix, path) = match base.find("://") {
        Some(i) => match base[i + 3..].find('/') {
            Some(j) => (&base[..i + 3 + j], &base[i + 3 + j..]),
            None => (base, ""),
        },
        None => ("", base),
    };

    let mut out = String::from(prefix);
    for seg in path.split('/') {
        if seg.is_empty() {
            continue;
        }
        out.push('/');
        let looks_like_value = seg.len() > 24
            || seg.contains('@')
            || seg.contains("%40")
            || seg.chars().all(|c| c.is_ascii_digit())
            || (seg.chars().any(|c| c.is_ascii_digit())
                && seg.chars().any(|c| c == '-' || c == '_'));
        if looks_like_value {
            out.push_str(":x");
        } else {
            out.push_str(seg);
        }
    }
    if base.contains('?') {
        out.push_str("?:x");
    }
    out
}

#[cfg(test)]
mod tests {
    use super::redact_route;

    #[test]
    fn secrets_in_the_path_are_redacted() {
        let cases = [
            ("https://api.example.com/account/confirm/482913", "482913"),
            (
                "https://api.example.com/user/maria%40empresa.com/reset",
                "maria",
            ),
            (
                "https://api.example.com/server/5c4a2f40-981b-49a2-8cee-eb169351cbf5",
                "5c4a2f40",
            ),
            ("https://api.example.com/auth?token=abcdef123456", "abcdef"),
        ];
        for (url, secret) in cases {
            let redacted = redact_route(url);
            assert!(
                !redacted.contains(secret),
                "leaked {secret:?} in {redacted:?}"
            );
        }
    }

    #[test]
    fn the_shape_of_the_route_survives() {
        let redacted = redact_route("https://api.example.com/account/confirm/482913");
        assert!(
            redacted.contains("api.example.com"),
            "lost the host: {redacted}"
        );
        assert!(
            redacted.contains("account"),
            "lost the resource: {redacted}"
        );
        assert!(redacted.contains("confirm"), "lost the action: {redacted}");
    }

    #[test]
    fn the_whole_query_string_is_dropped() {
        let redacted = redact_route("https://api.example.com/x?token=secret&user=maria");
        assert!(!redacted.contains("secret"));
        assert!(!redacted.contains("maria"));
    }
}
