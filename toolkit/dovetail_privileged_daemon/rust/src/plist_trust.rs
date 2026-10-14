use std::os::unix::fs::MetadataExt;
use std::path::Path;

pub(crate) fn closed_to_all_but_root(uid: u32, gid: u32, mode: u32) -> bool {
    uid == 0 && gid == 0 && mode & 0o022 == 0
}

pub(crate) fn system_plist_is_trusted(path: &Path) -> bool {
    std::fs::symlink_metadata(path).is_ok_and(|meta| {
        meta.is_file() && closed_to_all_but_root(meta.uid(), meta.gid(), meta.mode())
    })
}
