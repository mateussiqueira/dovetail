mod endpoint;
mod envelope;
mod framing;
mod handshake;
mod handshake_error;
mod handshake_server;
#[cfg(test)]
mod handshake_server_tests;
mod limits;
mod peer_auth;
mod transport;

pub use endpoint::Endpoint;
pub use envelope::{ErrorBody, ErrorCode, Request, RespPayload, Response};
pub use framing::{framer, recv_frame, send_frame, Framer, RecvError, SendError};
pub use handshake::{Frame, Hello, PeerCheck, ServerHello};
pub use handshake_error::HandshakeError;
pub use handshake_server::{server_handshake, ServerConfig, ServerHandshakeResult};
pub use limits::{
    HANDSHAKE_TIMEOUT_MS, IDLE_TIMEOUT_MS, MAX_FRAME_BYTES, PROTOCOL_MAJOR, PROTOCOL_MINOR,
};
pub use peer_auth::verify_peer;
pub use transport::{bind, Listener, Stream};
