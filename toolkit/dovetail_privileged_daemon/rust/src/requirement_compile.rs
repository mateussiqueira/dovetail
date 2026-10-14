use std::ffi::c_void;
use std::ptr;

type CfRef = *const c_void;

const UTF8: u32 = 0x0800_0100;

#[link(name = "CoreFoundation", kind = "framework")]
extern "C" {
    fn CFStringCreateWithBytes(
        allocator: CfRef,
        bytes: *const u8,
        length: isize,
        encoding: u32,
        external: u8,
    ) -> CfRef;
    fn CFDataGetLength(data: CfRef) -> isize;
    fn CFDataGetBytePtr(data: CfRef) -> *const u8;
    fn CFRelease(object: CfRef);
}

#[link(name = "Security", kind = "framework")]
extern "C" {
    fn SecRequirementCreateWithString(text: CfRef, flags: u32, requirement: *mut CfRef) -> i32;
    fn SecRequirementCopyData(requirement: CfRef, flags: u32, data: *mut CfRef) -> i32;
}

struct Owned(CfRef);

impl Drop for Owned {
    fn drop(&mut self) {
        unsafe { CFRelease(self.0) }
    }
}

fn owned(status: i32, object: CfRef, call: &str) -> anyhow::Result<Owned> {
    anyhow::ensure!(
        status == 0 && !object.is_null(),
        "{call} devolveu OSStatus {status}"
    );
    Ok(Owned(object))
}

pub(crate) fn compile_requirement(text: &str) -> anyhow::Result<Vec<u8>> {
    let length = text.len() as isize;
    let string = unsafe { CFStringCreateWithBytes(ptr::null(), text.as_ptr(), length, UTF8, 0) };
    let string = owned(0, string, "CFStringCreateWithBytes")?;
    let mut requirement = ptr::null();
    let status = unsafe { SecRequirementCreateWithString(string.0, 0, &mut requirement) };
    let requirement = owned(status, requirement, "SecRequirementCreateWithString")?;
    let mut data = ptr::null();
    let status = unsafe { SecRequirementCopyData(requirement.0, 0, &mut data) };
    let data = owned(status, data, "SecRequirementCopyData")?;
    let bytes = unsafe { CFDataGetBytePtr(data.0) };
    anyhow::ensure!(
        !bytes.is_null(),
        "SecRequirementCopyData devolveu dados vazios"
    );
    let length = unsafe { CFDataGetLength(data.0) } as usize;
    Ok(unsafe { std::slice::from_raw_parts(bytes, length) }.to_vec())
}
