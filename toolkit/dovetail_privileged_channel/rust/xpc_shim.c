#include <xpc/xpc.h>
#include <dispatch/dispatch.h>
#include <stdint.h>

typedef void (*dt_bytes_fn)(void *ctx, const void *bytes, size_t len);
typedef void *(*dt_peer_fn)(void *ctx, xpc_connection_t peer);
typedef void (*dt_free_fn)(void *ctx);

static void dt_route(xpc_connection_t conn, void *ctx, dt_bytes_fn on_bytes, dt_free_fn on_free) {
    xpc_connection_set_context(conn, ctx);
    xpc_connection_set_finalizer_f(conn, on_free);
    xpc_connection_set_event_handler(conn, ^(xpc_object_t event) {
        if (xpc_get_type(event) != XPC_TYPE_DICTIONARY) {
            if (event == XPC_ERROR_PEER_CODE_SIGNING_REQUIREMENT) xpc_connection_cancel(conn);
            on_bytes(ctx, NULL, 0);
            return;
        }
        size_t len = 0;
        const void *bytes = xpc_dictionary_get_data(event, "f", &len);
        if (bytes && len) on_bytes(ctx, bytes, len);
    });
}

xpc_connection_t dovetail_xpc_listen(const char *service, const char *requirement, void *ctx,
                                     dt_free_fn ctx_free, dt_peer_fn on_peer, dt_bytes_fn on_bytes,
                                     dt_free_fn peer_free) {
    if (service && !requirement) {
        ctx_free(ctx);
        return NULL;
    }
    dispatch_queue_t queue = dispatch_queue_create("dovetail.xpc.listener", DISPATCH_QUEUE_SERIAL);
    xpc_connection_t listener = service
        ? xpc_connection_create_mach_service(service, queue, XPC_CONNECTION_MACH_SERVICE_LISTENER)
        : xpc_connection_create(NULL, queue);
    dispatch_release(queue);
    xpc_connection_set_context(listener, ctx);
    xpc_connection_set_finalizer_f(listener, ctx_free);
    xpc_connection_set_event_handler(listener, ^(xpc_object_t event) {
        if (xpc_get_type(event) != XPC_TYPE_CONNECTION) {
            (void)on_peer(ctx, NULL);
            return;
        }
        xpc_connection_t peer = (xpc_connection_t)event;
        if (requirement && xpc_connection_set_peer_code_signing_requirement(peer, requirement) != 0) {
            xpc_connection_cancel(peer);
            return;
        }
        void *peer_ctx = on_peer(ctx, peer);
        if (!peer_ctx) return;
        dt_route(peer, peer_ctx, on_bytes, peer_free);
        xpc_connection_resume(peer);
    });
    xpc_connection_resume(listener);
    return listener;
}

xpc_connection_t dovetail_xpc_connect(const char *service, xpc_endpoint_t endpoint, uint64_t flags,
                                      void *ctx, dt_bytes_fn on_bytes, dt_free_fn ctx_free) {
    xpc_connection_t conn = endpoint
        ? xpc_connection_create_from_endpoint(endpoint)
        : xpc_connection_create_mach_service(service, NULL, flags);
    dt_route(conn, ctx, on_bytes, ctx_free);
    xpc_connection_resume(conn);
    return conn;
}

void dovetail_xpc_send(xpc_connection_t conn, const void *bytes, size_t len) {
    xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_data(message, "f", bytes, len);
    xpc_connection_send_message(conn, message);
    xpc_release(message);
}

void dovetail_xpc_flush(xpc_connection_t conn) {
    dispatch_semaphore_t sent = dispatch_semaphore_create(0);
    dispatch_retain(sent);
    xpc_connection_send_barrier(conn, ^{
        dispatch_semaphore_signal(sent);
        dispatch_release(sent);
    });
    dispatch_semaphore_wait(sent, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    dispatch_release(sent);
}
