use dovetail_rust_core::log_lines;

#[test]
fn a_line_emitted_on_any_thread_reaches_every_stream() {
    let mut first = log_lines().unwrap();
    let mut second = log_lines().unwrap();

    std::thread::spawn(|| tracing::warn!(target: "worker", "from another thread"))
        .join()
        .unwrap();

    assert_eq!(
        first.try_recv().unwrap(),
        "WARN worker: from another thread"
    );
    assert_eq!(
        second.try_recv().unwrap(),
        "WARN worker: from another thread"
    );
}
