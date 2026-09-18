use super::*;
use crate::error::ApiErrorPayload;
use serde::de::DeserializeOwned;
use sha2::{Digest, Sha256};

pub fn boundary_for(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    format!("----dovetail-{}", hex::encode(&digest[..12]))
}

fn safe_filename(filename: &str) -> String {
    filename
        .replace(['"', '\r', '\n', '\\'], "_")
        .trim()
        .to_string()
}

pub fn multipart_body(boundary: &str, filename: &str, content_type: &str, bytes: &[u8]) -> Vec<u8> {
    let mut body = Vec::with_capacity(bytes.len() + 256);
    body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
    body.extend_from_slice(
        format!(
            "Content-Disposition: form-data; name=\"file\"; filename=\"{}\"\r\n",
            safe_filename(filename)
        )
        .as_bytes(),
    );
    body.extend_from_slice(format!("Content-Type: {content_type}\r\n\r\n").as_bytes());
    body.extend_from_slice(bytes);
    body.extend_from_slice(format!("\r\n--{boundary}--\r\n").as_bytes());
    body
}

impl ApiClient {
    pub async fn post_multipart_file<R>(
        &self,
        path: &str,
        filename: &str,
        content_type: &str,
        bytes: &[u8],
    ) -> Result<R, ApiError>
    where
        R: DeserializeOwned,
    {
        let token = self
            .token_store
            .get_token()?
            .ok_or(ApiError::MissingToken)?;

        let boundary = boundary_for(bytes);
        let body = multipart_body(&boundary, filename, content_type, bytes);

        let resp = self
            .http
            .post(self.url(path))
            .bearer_auth(token)
            .header(
                reqwest::header::CONTENT_TYPE,
                format!("multipart/form-data; boundary={boundary}"),
            )
            .body(body)
            .send()
            .await
            .map_err(ApiError::Transport)?;

        let status = resp.status();
        if !status.is_success() {
            let err = resp.json::<ApiErrorPayload>().await.ok();
            return Err(Self::map_status_error(status, err));
        }

        resp.json::<R>().await.map_err(ApiError::Decode)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn body_text(boundary: &str, filename: &str, kind: &str, bytes: &[u8]) -> String {
        String::from_utf8(multipart_body(boundary, filename, kind, bytes)).unwrap()
    }

    #[test]
    fn the_body_opens_and_closes_with_the_boundary() {
        let body = body_text("EDGE", "note.txt", "text/plain", b"hi");
        assert!(body.starts_with("--EDGE\r\n"));
        assert!(body.ends_with("\r\n--EDGE--\r\n"));
    }

    #[test]
    fn the_field_is_the_one_the_backend_reads_and_carries_the_filename() {
        let body = body_text("EDGE", "note.txt", "text/plain", b"hi");
        assert!(body
            .contains("Content-Disposition: form-data; name=\"file\"; filename=\"note.txt\"\r\n"));
        assert!(body.contains("Content-Type: text/plain\r\n\r\n"));
    }

    #[test]
    fn the_content_travels_intact_between_the_headers() {
        let body = multipart_body("EDGE", "a.bin", "application/octet-stream", &[0, 1, 2, 255]);
        let start = body
            .windows(4)
            .position(|w| w == b"\r\n\r\n")
            .expect("end of headers");
        assert_eq!(&body[start + 4..start + 8], &[0, 1, 2, 255]);
    }

    #[test]
    fn the_filename_does_not_inject_a_header() {
        let body = body_text("EDGE", "a\r\nX-Evil: 1\r\n\r\nb", "text/plain", b"x");
        assert!(
            !body.lines().any(|line| line.starts_with("X-Evil:")),
            "{body}"
        );
        assert_eq!(body.matches("\r\n\r\n").count(), 1, "{body}");
    }

    #[test]
    fn quotes_and_backslashes_in_the_name_do_not_break_the_header() {
        let body = body_text("EDGE", "re\"port\\file.pdf", "application/pdf", b"x");
        assert!(body.contains("filename=\"re_port_file.pdf\""));
    }

    #[test]
    fn the_boundary_does_not_appear_in_the_body() {
        for content in [b"anything".as_slice(), b"", &[0u8; 64]] {
            let boundary = boundary_for(content);
            let body = multipart_body(&boundary, "a.bin", "application/octet-stream", content);
            let body = String::from_utf8_lossy(&body);
            assert_eq!(body.matches(&boundary).count(), 2, "{body}");
        }
    }

    #[test]
    fn the_boundary_is_stable_for_the_same_content() {
        assert_eq!(boundary_for(b"hi"), boundary_for(b"hi"));
        assert_ne!(boundary_for(b"hi"), boundary_for(b"hello"));
    }
}
