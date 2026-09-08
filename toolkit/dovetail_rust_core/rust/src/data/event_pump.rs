use tokio::sync::broadcast::error::RecvError;
use tokio::sync::broadcast::Receiver;

pub async fn pump<T, F>(mut receiver: Receiver<T>, mut emit: F)
where
    T: Clone,
    F: FnMut(T) -> bool,
{
    loop {
        match receiver.recv().await {
            Ok(event) => {
                if !emit(event) {
                    break;
                }
            }
            Err(RecvError::Lagged(lost)) => {
                tracing::warn!(lost, "event pump lagged; resuming");
                continue;
            }
            Err(RecvError::Closed) => break,
        }
    }
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Mutex};
    use std::time::Duration;

    use tokio::sync::broadcast;

    use super::*;

    #[tokio::test]
    async fn pump_resumes_after_a_lagging_receiver() {
        let (sender, receiver) = broadcast::channel::<u32>(2);
        for value in 0..8 {
            sender.send(value).unwrap();
        }

        let seen = Arc::new(Mutex::new(Vec::<u32>::new()));
        let collected = seen.clone();
        let pumping = tokio::spawn(async move {
            pump(receiver, move |value| {
                collected.lock().unwrap().push(value);
                true
            })
            .await;
        });

        tokio::time::sleep(Duration::from_millis(50)).await;
        sender.send(999).unwrap();
        tokio::time::sleep(Duration::from_millis(50)).await;
        drop(sender);
        pumping.await.unwrap();

        let delivered = seen.lock().unwrap().clone();
        assert!(
            delivered.contains(&999),
            "the pump ended at the lag instead of resuming: {delivered:?}"
        );
    }

    #[tokio::test]
    async fn pump_stops_when_the_sink_refuses() {
        let (sender, receiver) = broadcast::channel::<u32>(8);
        sender.send(1).unwrap();
        sender.send(2).unwrap();

        let count = Arc::new(Mutex::new(0_usize));
        let counted = count.clone();
        pump(receiver, move |_| {
            *counted.lock().unwrap() += 1;
            false
        })
        .await;

        assert_eq!(*count.lock().unwrap(), 1);
    }

    #[tokio::test]
    async fn pump_ends_when_every_sender_is_gone() {
        let (sender, receiver) = broadcast::channel::<u32>(8);
        sender.send(1).unwrap();
        drop(sender);

        let seen = Arc::new(Mutex::new(Vec::<u32>::new()));
        let collected = seen.clone();
        pump(receiver, move |value| {
            collected.lock().unwrap().push(value);
            true
        })
        .await;

        assert_eq!(*seen.lock().unwrap(), vec![1]);
    }
}
