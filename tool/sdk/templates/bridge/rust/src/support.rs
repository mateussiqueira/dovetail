use std::future::Future;

use dovetail_rust_core::run_on_runtime;

/// O repasse padrão: roda o future no runtime do dovetail_rust_core e devolve o
/// resultado com o erro achatado.
///
/// O fixture (`product/desktop_core_bridge`) converte o erro para o
/// `CoreFailure` tipado do produto; aqui o tipo é String porque o template
/// não conhece o crate de quem gera. Troque pelo tipo do seu produto.
pub(crate) async fn run<T, F>(future: F) -> Result<T, String>
where
    T: Send + 'static,
    F: Future<Output = Result<T, String>> + Send + 'static,
{
    match run_on_runtime(future).await {
        Ok(Ok(value)) => Ok(value),
        Ok(Err(error)) => Err(error),
        Err(bridge) => Err(bridge.to_string()),
    }
}
