use std::ffi::c_void;
use std::os::unix::io::RawFd;
use std::ptr;

use crate::handshake::PeerCheck;

type CfRef = *const c_void;

const UTF8: u32 = 0x0800_0100;

#[repr(C)]
struct CfCallBacks {
    _opaque: [u8; 0],
}

#[link(name = "CoreFoundation", kind = "framework")]
extern "C" {
    static kCFTypeDictionaryKeyCallBacks: CfCallBacks;
    static kCFTypeDictionaryValueCallBacks: CfCallBacks;
    fn CFDataCreate(allocator: CfRef, bytes: *const u8, length: isize) -> CfRef;
    fn CFDictionaryCreate(
        allocator: CfRef,
        keys: *const CfRef,
        values: *const CfRef,
        count: isize,
        key_callbacks: *const CfCallBacks,
        value_callbacks: *const CfCallBacks,
    ) -> CfRef;
    fn CFStringCreateWithBytes(
        allocator: CfRef,
        bytes: *const u8,
        length: isize,
        encoding: u32,
        external: u8,
    ) -> CfRef;
    fn CFRelease(object: CfRef);
}

#[link(name = "Security", kind = "framework")]
extern "C" {
    static kSecGuestAttributeAudit: CfRef;
    fn SecCodeCopyGuestWithAttributes(
        host: CfRef,
        attributes: CfRef,
        flags: u32,
        guest: *mut CfRef,
    ) -> i32;
    fn SecRequirementCreateWithString(text: CfRef, flags: u32, requirement: *mut CfRef) -> i32;
    fn SecCodeCheckValidity(code: CfRef, flags: u32, requirement: CfRef) -> i32;
}

pub(crate) struct AuditToken([u32; 8]);

impl AuditToken {
    pub(crate) fn of_peer(fd: RawFd) -> anyhow::Result<Self> {
        let mut token = [0u32; 8];
        let mut length = std::mem::size_of_val(&token) as libc::socklen_t;
        let read = unsafe {
            libc::getsockopt(
                fd,
                libc::SOL_LOCAL,
                libc::LOCAL_PEERTOKEN,
                token.as_mut_ptr().cast(),
                &mut length,
            )
        };
        if read != 0 {
            anyhow::bail!(
                "LOCAL_PEERTOKEN falhou: {}",
                std::io::Error::last_os_error()
            );
        }
        Ok(Self(token))
    }

    pub(crate) fn pid(&self) -> u32 {
        self.0[5]
    }
}

struct Owned(CfRef);

impl Owned {
    fn new(object: CfRef, call: &str) -> anyhow::Result<Self> {
        anyhow::ensure!(!object.is_null(), "{call} devolveu nulo");
        Ok(Self(object))
    }

    fn created(status: i32, object: CfRef, call: &str) -> anyhow::Result<Self> {
        anyhow::ensure!(status == 0, "{call} devolveu OSStatus {status}");
        Self::new(object, call)
    }
}

impl Drop for Owned {
    fn drop(&mut self) {
        unsafe { CFRelease(self.0) }
    }
}

fn requirement(text: &str) -> anyhow::Result<Owned> {
    let length = text.len() as isize;
    let string = unsafe { CFStringCreateWithBytes(ptr::null(), text.as_ptr(), length, UTF8, 0) };
    let string = Owned::new(string, "CFStringCreateWithBytes")?;
    let mut requirement = ptr::null();
    let status = unsafe { SecRequirementCreateWithString(string.0, 0, &mut requirement) };
    Owned::created(status, requirement, "SecRequirementCreateWithString")
}

fn guest(token: &AuditToken) -> anyhow::Result<Owned> {
    let length = std::mem::size_of_val(&token.0) as isize;
    let data = unsafe { CFDataCreate(ptr::null(), token.0.as_ptr().cast(), length) };
    let data = Owned::new(data, "CFDataCreate")?;
    let attributes = unsafe {
        CFDictionaryCreate(
            ptr::null(),
            ptr::addr_of!(kSecGuestAttributeAudit),
            &data.0,
            1,
            ptr::addr_of!(kCFTypeDictionaryKeyCallBacks),
            ptr::addr_of!(kCFTypeDictionaryValueCallBacks),
        )
    };
    let attributes = Owned::new(attributes, "CFDictionaryCreate")?;
    let mut code = ptr::null();
    let status = unsafe { SecCodeCopyGuestWithAttributes(ptr::null(), attributes.0, 0, &mut code) };
    Owned::created(status, code, "SecCodeCopyGuestWithAttributes")
}

pub(crate) fn check(fd: RawFd, text: &str) -> anyhow::Result<PeerCheck> {
    let requirement = requirement(text)?;
    let token = AuditToken::of_peer(fd)?;
    let pid = token.pid();
    let code = guest(&token)?;
    let status = unsafe { SecCodeCheckValidity(code.0, 0, requirement.0) };
    anyhow::ensure!(
        status == 0,
        "pid={pid} recusado: o codigo do peer nao satisfaz o requisito do produto \
         (OSStatus {status})"
    );
    Ok(PeerCheck {
        method: "peertoken+codesign".to_string(),
        subject: format!("pid={pid}"),
    })
}
