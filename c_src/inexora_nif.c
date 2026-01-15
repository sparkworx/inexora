// c_src/inexora_nif.c
// Inexora NIF - Oracle Database driver for Elixir via ODPI-C

#include <erl_nif.h>
#include <string.h>
#include "dpi.h"

// Resource types
static ErlNifResourceType *CONTEXT_RESOURCE_TYPE;
static ErlNifResourceType *CONNECTION_RESOURCE_TYPE;

// Connection resource struct - holds both context and connection
typedef struct {
    dpiContext *context;
    dpiConn *conn;
} InexoraConnection;

// Atoms (initialized in on_load)
static ERL_NIF_TERM ATOM_OK;
static ERL_NIF_TERM ATOM_ERROR;
static ERL_NIF_TERM ATOM_NIL;
static ERL_NIF_TERM ATOM_TRUE;
static ERL_NIF_TERM ATOM_FALSE;

// Helper: make {:ok, value} tuple
static ERL_NIF_TERM make_ok_tuple(ErlNifEnv *env, ERL_NIF_TERM value) {
    return enif_make_tuple2(env, ATOM_OK, value);
}

// Helper: make {:error, reason} tuple
static ERL_NIF_TERM make_error_tuple(ErlNifEnv *env, const char *reason) {
    return enif_make_tuple2(env, ATOM_ERROR,
        enif_make_string(env, reason, ERL_NIF_LATIN1));
}

// Helper: make {:error, dpiErrorInfo} tuple with details
static ERL_NIF_TERM make_dpi_error(ErlNifEnv *env, dpiErrorInfo *errorInfo) {
    return enif_make_tuple2(env, ATOM_ERROR,
        enif_make_tuple3(env,
            enif_make_int(env, errorInfo->code),
            enif_make_string(env, errorInfo->fnName ? errorInfo->fnName : "unknown", ERL_NIF_LATIN1),
            enif_make_string_len(env, errorInfo->message, errorInfo->messageLength, ERL_NIF_LATIN1)
        ));
}

// Context destructor (called when Erlang garbage collects the resource)
static void context_destructor(ErlNifEnv *env, void *obj) {
    (void)env;
    dpiContext **ctx_ptr = (dpiContext **)obj;
    if (*ctx_ptr != NULL) {
        dpiContext_destroy(*ctx_ptr);
        *ctx_ptr = NULL;
    }
}

// Connection destructor (called when Erlang garbage collects the resource)
static void connection_destructor(ErlNifEnv *env, void *obj) {
    (void)env;
    InexoraConnection *conn_res = (InexoraConnection *)obj;
    if (conn_res->conn != NULL) {
        dpiConn_release(conn_res->conn);
        conn_res->conn = NULL;
    }
    // Note: We don't destroy the context here as it's managed separately
}

// ============================================================
// NIF Functions
// ============================================================

// Get ODPI-C library version (no context needed)
// Returns: {:ok, {major, minor, patch}} | {:error, reason}
static ERL_NIF_TERM nif_odpi_version(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    (void)argv;

    ERL_NIF_TERM version = enif_make_tuple3(env,
        enif_make_int(env, DPI_MAJOR_VERSION),
        enif_make_int(env, DPI_MINOR_VERSION),
        enif_make_int(env, DPI_PATCH_LEVEL)
    );

    return make_ok_tuple(env, version);
}

// Create ODPI-C context
// Returns: {:ok, context_ref} | {:error, reason}
static ERL_NIF_TERM nif_context_create(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    (void)argv;

    dpiErrorInfo errorInfo;
    dpiContext *context = NULL;

    // Create context using ODPI-C
    if (dpiContext_createWithParams(DPI_MAJOR_VERSION, DPI_MINOR_VERSION,
            NULL, &context, &errorInfo) < 0) {
        return make_dpi_error(env, &errorInfo);
    }

    // Wrap context in Erlang resource
    dpiContext **ctx_res = enif_alloc_resource(CONTEXT_RESOURCE_TYPE, sizeof(dpiContext *));
    *ctx_res = context;

    ERL_NIF_TERM result = enif_make_resource(env, ctx_res);
    enif_release_resource(ctx_res);

    return make_ok_tuple(env, result);
}

// Destroy ODPI-C context
// Returns: :ok | {:error, reason}
static ERL_NIF_TERM nif_context_destroy(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 1) {
        return enif_make_badarg(env);
    }

    dpiContext **ctx_res;
    if (!enif_get_resource(env, argv[0], CONTEXT_RESOURCE_TYPE, (void **)&ctx_res)) {
        return make_error_tuple(env, "invalid_context");
    }

    if (*ctx_res != NULL) {
        dpiContext_destroy(*ctx_res);
        *ctx_res = NULL;
    }

    return ATOM_OK;
}

// Get Oracle client version (requires context, but NOT a connection)
// Returns: {:ok, {version, release, update, port_release, port_update}} | {:error, reason}
static ERL_NIF_TERM nif_get_client_version(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 1) {
        return enif_make_badarg(env);
    }

    dpiContext **ctx_res;
    if (!enif_get_resource(env, argv[0], CONTEXT_RESOURCE_TYPE, (void **)&ctx_res)) {
        return make_error_tuple(env, "invalid_context");
    }

    if (*ctx_res == NULL) {
        return make_error_tuple(env, "context_destroyed");
    }

    dpiVersionInfo versionInfo;
    if (dpiContext_getClientVersion(*ctx_res, &versionInfo) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(*ctx_res, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    ERL_NIF_TERM version = enif_make_tuple5(env,
        enif_make_int(env, versionInfo.versionNum),
        enif_make_int(env, versionInfo.releaseNum),
        enif_make_int(env, versionInfo.updateNum),
        enif_make_int(env, versionInfo.portReleaseNum),
        enif_make_int(env, versionInfo.portUpdateNum)
    );

    return make_ok_tuple(env, version);
}

// ============================================================
// Connection NIF Functions
// ============================================================

// Create database connection
// conn_create(context, username, password, connect_string) -> {:ok, conn} | {:error, reason}
static ERL_NIF_TERM nif_conn_create(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 4) {
        return enif_make_badarg(env);
    }

    // Get context resource
    dpiContext **ctx_res;
    if (!enif_get_resource(env, argv[0], CONTEXT_RESOURCE_TYPE, (void **)&ctx_res)) {
        return make_error_tuple(env, "invalid_context");
    }
    if (*ctx_res == NULL) {
        return make_error_tuple(env, "context_destroyed");
    }

    // Get username
    ErlNifBinary username_bin;
    if (!enif_inspect_binary(env, argv[1], &username_bin)) {
        return make_error_tuple(env, "invalid_username");
    }

    // Get password
    ErlNifBinary password_bin;
    if (!enif_inspect_binary(env, argv[2], &password_bin)) {
        return make_error_tuple(env, "invalid_password");
    }

    // Get connect string
    ErlNifBinary connect_string_bin;
    if (!enif_inspect_binary(env, argv[3], &connect_string_bin)) {
        return make_error_tuple(env, "invalid_connect_string");
    }

    // Create connection
    dpiConn *conn = NULL;
    if (dpiConn_create(*ctx_res,
            (const char *)username_bin.data, username_bin.size,
            (const char *)password_bin.data, password_bin.size,
            (const char *)connect_string_bin.data, connect_string_bin.size,
            NULL, NULL, &conn) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(*ctx_res, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    // Wrap connection in Erlang resource (includes context reference for error retrieval)
    InexoraConnection *conn_res = enif_alloc_resource(CONNECTION_RESOURCE_TYPE, sizeof(InexoraConnection));
    conn_res->context = *ctx_res;
    conn_res->conn = conn;

    ERL_NIF_TERM result = enif_make_resource(env, conn_res);
    enif_release_resource(conn_res);

    return make_ok_tuple(env, result);
}

// Close database connection
// conn_close(conn) -> :ok | {:error, reason}
static ERL_NIF_TERM nif_conn_close(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 1) {
        return enif_make_badarg(env);
    }

    InexoraConnection *conn_res;
    if (!enif_get_resource(env, argv[0], CONNECTION_RESOURCE_TYPE, (void **)&conn_res)) {
        return make_error_tuple(env, "invalid_connection");
    }

    if (conn_res->conn != NULL) {
        // Close with default mode
        dpiConn_close(conn_res->conn, DPI_MODE_CONN_CLOSE_DEFAULT, NULL, 0);
        dpiConn_release(conn_res->conn);
        conn_res->conn = NULL;
    }

    return ATOM_OK;
}

// Ping database connection
// conn_ping(conn) -> :ok | {:error, reason}
static ERL_NIF_TERM nif_conn_ping(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 1) {
        return enif_make_badarg(env);
    }

    InexoraConnection *conn_res;
    if (!enif_get_resource(env, argv[0], CONNECTION_RESOURCE_TYPE, (void **)&conn_res)) {
        return make_error_tuple(env, "invalid_connection");
    }

    if (conn_res->conn == NULL) {
        return make_error_tuple(env, "connection_closed");
    }

    if (dpiConn_ping(conn_res->conn) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(conn_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    return ATOM_OK;
}

// Commit transaction
// conn_commit(conn) -> :ok | {:error, reason}
static ERL_NIF_TERM nif_conn_commit(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 1) {
        return enif_make_badarg(env);
    }

    InexoraConnection *conn_res;
    if (!enif_get_resource(env, argv[0], CONNECTION_RESOURCE_TYPE, (void **)&conn_res)) {
        return make_error_tuple(env, "invalid_connection");
    }

    if (conn_res->conn == NULL) {
        return make_error_tuple(env, "connection_closed");
    }

    if (dpiConn_commit(conn_res->conn) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(conn_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    return ATOM_OK;
}

// Rollback transaction
// conn_rollback(conn) -> :ok | {:error, reason}
static ERL_NIF_TERM nif_conn_rollback(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 1) {
        return enif_make_badarg(env);
    }

    InexoraConnection *conn_res;
    if (!enif_get_resource(env, argv[0], CONNECTION_RESOURCE_TYPE, (void **)&conn_res)) {
        return make_error_tuple(env, "invalid_connection");
    }

    if (conn_res->conn == NULL) {
        return make_error_tuple(env, "connection_closed");
    }

    if (dpiConn_rollback(conn_res->conn) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(conn_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    return ATOM_OK;
}

// Get server version
// conn_get_server_version(conn) -> {:ok, {release_string, {ver, rel, update, port_rel, port_update}}} | {:error, reason}
static ERL_NIF_TERM nif_conn_get_server_version(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 1) {
        return enif_make_badarg(env);
    }

    InexoraConnection *conn_res;
    if (!enif_get_resource(env, argv[0], CONNECTION_RESOURCE_TYPE, (void **)&conn_res)) {
        return make_error_tuple(env, "invalid_connection");
    }

    if (conn_res->conn == NULL) {
        return make_error_tuple(env, "connection_closed");
    }

    const char *releaseString;
    uint32_t releaseStringLength;
    dpiVersionInfo versionInfo;

    if (dpiConn_getServerVersion(conn_res->conn, &releaseString, &releaseStringLength, &versionInfo) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(conn_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    ERL_NIF_TERM release_str = enif_make_string_len(env, releaseString, releaseStringLength, ERL_NIF_LATIN1);
    ERL_NIF_TERM version_tuple = enif_make_tuple5(env,
        enif_make_int(env, versionInfo.versionNum),
        enif_make_int(env, versionInfo.releaseNum),
        enif_make_int(env, versionInfo.updateNum),
        enif_make_int(env, versionInfo.portReleaseNum),
        enif_make_int(env, versionInfo.portUpdateNum)
    );

    return make_ok_tuple(env, enif_make_tuple2(env, release_str, version_tuple));
}

// Check if connection is healthy (no round-trip)
// conn_get_is_healthy(conn) -> {:ok, boolean()} | {:error, reason}
static ERL_NIF_TERM nif_conn_get_is_healthy(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 1) {
        return enif_make_badarg(env);
    }

    InexoraConnection *conn_res;
    if (!enif_get_resource(env, argv[0], CONNECTION_RESOURCE_TYPE, (void **)&conn_res)) {
        return make_error_tuple(env, "invalid_connection");
    }

    if (conn_res->conn == NULL) {
        return make_error_tuple(env, "connection_closed");
    }

    int isHealthy;
    if (dpiConn_getIsHealthy(conn_res->conn, &isHealthy) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(conn_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    return make_ok_tuple(env, isHealthy ? ATOM_TRUE : ATOM_FALSE);
}

// Check if transaction is in progress
// conn_get_transaction_in_progress(conn) -> {:ok, boolean()} | {:error, reason}
static ERL_NIF_TERM nif_conn_get_transaction_in_progress(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 1) {
        return enif_make_badarg(env);
    }

    InexoraConnection *conn_res;
    if (!enif_get_resource(env, argv[0], CONNECTION_RESOURCE_TYPE, (void **)&conn_res)) {
        return make_error_tuple(env, "invalid_connection");
    }

    if (conn_res->conn == NULL) {
        return make_error_tuple(env, "connection_closed");
    }

    int inProgress;
    if (dpiConn_getTransactionInProgress(conn_res->conn, &inProgress) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(conn_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    return make_ok_tuple(env, inProgress ? ATOM_TRUE : ATOM_FALSE);
}

// ============================================================
// NIF Registration
// ============================================================

static ErlNifFunc nif_funcs[] = {
    // Context functions
    {"odpi_version", 0, nif_odpi_version, 0},
    {"context_create", 0, nif_context_create, 0},
    {"context_destroy", 1, nif_context_destroy, 0},
    {"get_client_version", 1, nif_get_client_version, 0},
    // Connection functions (network I/O marked as dirty)
    {"conn_create", 4, nif_conn_create, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"conn_close", 1, nif_conn_close, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"conn_ping", 1, nif_conn_ping, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"conn_commit", 1, nif_conn_commit, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"conn_rollback", 1, nif_conn_rollback, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"conn_get_server_version", 1, nif_conn_get_server_version, 0},
    {"conn_get_is_healthy", 1, nif_conn_get_is_healthy, 0},
    {"conn_get_transaction_in_progress", 1, nif_conn_get_transaction_in_progress, 0}
};

// on_load callback - initialize resources and atoms
static int on_load(ErlNifEnv *env, void **priv_data, ERL_NIF_TERM load_info) {
    (void)priv_data;
    (void)load_info;

    // Create atoms
    ATOM_OK = enif_make_atom(env, "ok");
    ATOM_ERROR = enif_make_atom(env, "error");
    ATOM_NIL = enif_make_atom(env, "nil");
    ATOM_TRUE = enif_make_atom(env, "true");
    ATOM_FALSE = enif_make_atom(env, "false");

    // Register resource types
    CONTEXT_RESOURCE_TYPE = enif_open_resource_type(
        env,
        NULL,
        "inexora_context",
        context_destructor,
        ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER,
        NULL
    );

    if (CONTEXT_RESOURCE_TYPE == NULL) {
        return -1;
    }

    CONNECTION_RESOURCE_TYPE = enif_open_resource_type(
        env,
        NULL,
        "inexora_connection",
        connection_destructor,
        ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER,
        NULL
    );

    if (CONNECTION_RESOURCE_TYPE == NULL) {
        return -1;
    }

    return 0;
}

// on_upgrade callback
static int on_upgrade(ErlNifEnv *env, void **priv_data, void **old_priv_data, ERL_NIF_TERM load_info) {
    (void)env;
    (void)priv_data;
    (void)old_priv_data;
    (void)load_info;
    return 0;
}

// Register the NIF module
ERL_NIF_INIT(Elixir.Inexora.Nif, nif_funcs, on_load, NULL, on_upgrade, NULL)
