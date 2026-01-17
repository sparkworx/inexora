// c_src/inexora_nif.c
// Inexora NIF - Oracle Database driver for Elixir via ODPI-C

#include <erl_nif.h>
#include <string.h>
#include <stdio.h>
#include "dpi.h"

// Resource types
static ErlNifResourceType *CONTEXT_RESOURCE_TYPE;
static ErlNifResourceType *CONNECTION_RESOURCE_TYPE;
static ErlNifResourceType *STATEMENT_RESOURCE_TYPE;
static ErlNifResourceType *VARIABLE_RESOURCE_TYPE;

// Connection resource struct - holds both context and connection
typedef struct {
    dpiContext *context;
    dpiConn *conn;
    volatile int closed;  // Flag to indicate connection has been closed (for thread safety)
    ErlNifMutex *mutex;   // Mutex to protect connection close operations
} InexoraConnection;

// Statement resource struct - holds context, connection, and statement
typedef struct {
    InexoraConnection *conn_resource;  // Reference to connection resource (prevents use-after-free)
    dpiContext *context;
    dpiConn *conn;
    dpiStmt *stmt;
} InexoraStatement;

// Variable resource struct - holds variable for array/batch operations
typedef struct {
    InexoraConnection *conn_resource;  // Reference to connection resource (prevents use-after-free)
    dpiContext *context;
    dpiConn *conn;
    dpiVar *var;
    dpiData *data;           // Pointer to array of dpiData elements
    uint32_t maxArraySize;   // Maximum number of elements in array
    dpiOracleTypeNum oracleTypeNum;
    dpiNativeTypeNum nativeTypeNum;
} InexoraVariable;

// Atoms (initialized in on_load)
static ERL_NIF_TERM ATOM_OK;
static ERL_NIF_TERM ATOM_ERROR;
static ERL_NIF_TERM ATOM_NIL;
static ERL_NIF_TERM ATOM_TRUE;
static ERL_NIF_TERM ATOM_FALSE;
static ERL_NIF_TERM ATOM_DONE;

// Context option atoms
static ERL_NIF_TERM ATOM_DRIVER_NAME;
static ERL_NIF_TERM ATOM_ORACLE_CLIENT_LIB_DIR;
static ERL_NIF_TERM ATOM_ORACLE_CLIENT_CONFIG_DIR;

// Helper: make {:ok, value} tuple
static ERL_NIF_TERM make_ok_tuple(ErlNifEnv *env, ERL_NIF_TERM value) {
    return enif_make_tuple2(env, ATOM_OK, value);
}

// Helper: make binary from null-terminated C string
static ERL_NIF_TERM make_binary_string(ErlNifEnv *env, const char *str) {
    size_t len = strlen(str);
    ERL_NIF_TERM bin;
    unsigned char *buf = enif_make_new_binary(env, len, &bin);
    memcpy(buf, str, len);
    return bin;
}

// Helper: make binary from C string with explicit length
static ERL_NIF_TERM make_binary_string_len(ErlNifEnv *env, const char *str, size_t len) {
    ERL_NIF_TERM bin;
    unsigned char *buf = enif_make_new_binary(env, len, &bin);
    memcpy(buf, str, len);
    return bin;
}

// Helper: make {:error, reason} tuple
static ERL_NIF_TERM make_error_tuple(ErlNifEnv *env, const char *reason) {
    return enif_make_tuple2(env, ATOM_ERROR, make_binary_string(env, reason));
}

// Helper: make {:error, dpiErrorInfo} tuple with details
static ERL_NIF_TERM make_dpi_error(ErlNifEnv *env, dpiErrorInfo *errorInfo) {
    return enif_make_tuple2(env, ATOM_ERROR,
        enif_make_tuple3(env,
            enif_make_int(env, errorInfo->code),
            make_binary_string(env, errorInfo->fnName ? errorInfo->fnName : "unknown"),
            make_binary_string_len(env, errorInfo->message, errorInfo->messageLength)
        ));
}

// ============================================================
// Context Options Parsing
// ============================================================

// Struct to hold parsed context creation options
typedef struct {
    char *driver_name;
    char *oracle_client_lib_dir;
    char *oracle_client_config_dir;
} ContextOptions;

// Initialize context options struct
static void context_options_init(ContextOptions *opts) {
    opts->driver_name = NULL;
    opts->oracle_client_lib_dir = NULL;
    opts->oracle_client_config_dir = NULL;
}

// Free allocated memory in context options struct
static void context_options_free(ContextOptions *opts) {
    if (opts->driver_name) {
        enif_free(opts->driver_name);
        opts->driver_name = NULL;
    }
    if (opts->oracle_client_lib_dir) {
        enif_free(opts->oracle_client_lib_dir);
        opts->oracle_client_lib_dir = NULL;
    }
    if (opts->oracle_client_config_dir) {
        enif_free(opts->oracle_client_config_dir);
        opts->oracle_client_config_dir = NULL;
    }
}

// Helper: allocate and copy binary to null-terminated string
static char *binary_to_cstring(ErlNifBinary *bin) {
    char *str = enif_alloc(bin->size + 1);
    if (str) {
        memcpy(str, bin->data, bin->size);
        str[bin->size] = '\0';
    }
    return str;
}

// Parse context options from keyword list
// Returns 0 on success, sets error_term on failure
static int parse_context_options(ErlNifEnv *env, ERL_NIF_TERM list,
                                  ContextOptions *opts, ERL_NIF_TERM *error_term) {
    ERL_NIF_TERM head, tail;
    ErlNifBinary bin;

    while (enif_get_list_cell(env, list, &head, &tail)) {
        int arity;
        const ERL_NIF_TERM *tuple;

        if (enif_get_tuple(env, head, &arity, &tuple) && arity == 2) {
            ERL_NIF_TERM key = tuple[0];
            ERL_NIF_TERM value = tuple[1];

            if (enif_is_identical(key, ATOM_DRIVER_NAME)) {
                if (!enif_inspect_binary(env, value, &bin)) {
                    *error_term = make_error_tuple(env, "driver_name_must_be_binary");
                    return -1;
                }
                opts->driver_name = binary_to_cstring(&bin);
                if (!opts->driver_name) {
                    *error_term = make_error_tuple(env, "allocation_failed");
                    return -1;
                }
            } else if (enif_is_identical(key, ATOM_ORACLE_CLIENT_LIB_DIR)) {
                if (!enif_inspect_binary(env, value, &bin)) {
                    *error_term = make_error_tuple(env, "oracle_client_lib_dir_must_be_binary");
                    return -1;
                }
                opts->oracle_client_lib_dir = binary_to_cstring(&bin);
                if (!opts->oracle_client_lib_dir) {
                    *error_term = make_error_tuple(env, "allocation_failed");
                    return -1;
                }
            } else if (enif_is_identical(key, ATOM_ORACLE_CLIENT_CONFIG_DIR)) {
                if (!enif_inspect_binary(env, value, &bin)) {
                    *error_term = make_error_tuple(env, "oracle_client_config_dir_must_be_binary");
                    return -1;
                }
                opts->oracle_client_config_dir = binary_to_cstring(&bin);
                if (!opts->oracle_client_config_dir) {
                    *error_term = make_error_tuple(env, "allocation_failed");
                    return -1;
                }
            }
            // Ignore unknown options for forward compatibility
        }
        list = tail;
    }

    return 0;
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

    // Lock the mutex to ensure no statement/variable destructors are in progress
    if (conn_res->mutex != NULL) {
        enif_mutex_lock(conn_res->mutex);
    }

    // Mark as closed FIRST before releasing.
    // This prevents statement/variable destructors from trying to use the connection.
    __atomic_store_n(&conn_res->closed, 1, __ATOMIC_RELEASE);

    if (conn_res->conn != NULL) {
        dpiConn_release(conn_res->conn);
        conn_res->conn = NULL;
    }

    if (conn_res->mutex != NULL) {
        enif_mutex_unlock(conn_res->mutex);
        enif_mutex_destroy(conn_res->mutex);
        conn_res->mutex = NULL;
    }
    // Note: We don't destroy the context here as it's managed separately
}

// Statement destructor (called when Erlang garbage collects the resource)
static void statement_destructor(ErlNifEnv *env, void *obj) {
    (void)env;
    InexoraStatement *stmt_res = (InexoraStatement *)obj;

    // Only release the statement if the connection is still valid.
    // When a connection is closed, all associated statements are implicitly
    // invalidated by Oracle. Attempting to release them causes a crash.
    // Use mutex to prevent race with connection close.
    if (stmt_res->stmt != NULL &&
        stmt_res->conn_resource != NULL &&
        stmt_res->conn_resource->mutex != NULL) {

        enif_mutex_lock(stmt_res->conn_resource->mutex);
        // Double-check closed flag while holding mutex
        if (!__atomic_load_n(&stmt_res->conn_resource->closed, __ATOMIC_ACQUIRE)) {
            dpiStmt_release(stmt_res->stmt);
        }
        enif_mutex_unlock(stmt_res->conn_resource->mutex);
    }
    stmt_res->stmt = NULL;

    // Release our reference to the connection resource
    if (stmt_res->conn_resource != NULL) {
        enif_release_resource(stmt_res->conn_resource);
        stmt_res->conn_resource = NULL;
    }
}

// Variable destructor (called when Erlang garbage collects the resource)
static void variable_destructor(ErlNifEnv *env, void *obj) {
    (void)env;
    InexoraVariable *var_res = (InexoraVariable *)obj;

    // Only release the variable if the connection is still valid.
    // When a connection is closed, all associated variables are implicitly
    // invalidated by Oracle. Attempting to release them causes a crash.
    // Use mutex to prevent race with connection close.
    if (var_res->var != NULL &&
        var_res->conn_resource != NULL &&
        var_res->conn_resource->mutex != NULL) {

        enif_mutex_lock(var_res->conn_resource->mutex);
        // Double-check closed flag while holding mutex
        if (!__atomic_load_n(&var_res->conn_resource->closed, __ATOMIC_ACQUIRE)) {
            dpiVar_release(var_res->var);
        }
        enif_mutex_unlock(var_res->conn_resource->mutex);
    }
    var_res->var = NULL;

    // Release our reference to the connection resource
    if (var_res->conn_resource != NULL) {
        enif_release_resource(var_res->conn_resource);
        var_res->conn_resource = NULL;
    }
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
// context_create(opts) -> {:ok, context_ref} | {:error, reason}
// opts is a keyword list: [{:driver_name, "..."}, {:oracle_client_lib_dir, "..."}, ...]
static ERL_NIF_TERM nif_context_create(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 1) {
        return enif_make_badarg(env);
    }

    // Parse options from keyword list
    ContextOptions opts;
    context_options_init(&opts);

    ERL_NIF_TERM error_term;
    if (parse_context_options(env, argv[0], &opts, &error_term) < 0) {
        context_options_free(&opts);
        return error_term;
    }

    // Initialize ODPI-C context params
    dpiContextCreateParams ctxParams;
    memset(&ctxParams, 0, sizeof(dpiContextCreateParams));

    ctxParams.defaultDriverName = opts.driver_name ? opts.driver_name : "Inexora : 0.1.0";
    ctxParams.oracleClientLibDir = opts.oracle_client_lib_dir;
    ctxParams.oracleClientConfigDir = opts.oracle_client_config_dir;

    // Create context using ODPI-C
    dpiErrorInfo errorInfo;
    dpiContext *context = NULL;
    int result = dpiContext_createWithParams(DPI_MAJOR_VERSION, DPI_MINOR_VERSION,
            &ctxParams, &context, &errorInfo);

    // Free options (no longer needed after context creation)
    context_options_free(&opts);

    if (result < 0) {
        return make_dpi_error(env, &errorInfo);
    }

    // Wrap context in Erlang resource
    dpiContext **ctx_res = enif_alloc_resource(CONTEXT_RESOURCE_TYPE, sizeof(dpiContext *));
    *ctx_res = context;

    ERL_NIF_TERM ctx_term = enif_make_resource(env, ctx_res);
    enif_release_resource(ctx_res);

    return make_ok_tuple(env, ctx_term);
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

    // Initialize common params with threaded mode for NIF thread safety
    dpiCommonCreateParams commonParams;
    if (dpiContext_initCommonCreateParams(*ctx_res, &commonParams) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(*ctx_res, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }
    commonParams.createMode = DPI_MODE_CREATE_THREADED;

    // Create connection
    dpiConn *conn = NULL;
    if (dpiConn_create(*ctx_res,
            (const char *)username_bin.data, username_bin.size,
            (const char *)password_bin.data, password_bin.size,
            (const char *)connect_string_bin.data, connect_string_bin.size,
            &commonParams, NULL, &conn) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(*ctx_res, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    // Wrap connection in Erlang resource (includes context reference for error retrieval)
    InexoraConnection *conn_res = enif_alloc_resource(CONNECTION_RESOURCE_TYPE, sizeof(InexoraConnection));
    conn_res->context = *ctx_res;
    conn_res->conn = conn;
    conn_res->closed = 0;  // Initialize closed flag
    conn_res->mutex = enif_mutex_create("inexora_conn_mutex");  // Create mutex for thread safety

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

    // Lock the mutex to ensure no statement/variable destructors are in progress
    if (conn_res->mutex != NULL) {
        enif_mutex_lock(conn_res->mutex);
    }

    if (conn_res->conn != NULL && !__atomic_load_n(&conn_res->closed, __ATOMIC_ACQUIRE)) {
        // Mark as closed atomically FIRST to prevent statement/variable destructors from
        // trying to release resources after we close the connection.
        // This is critical for thread safety - statements may be garbage collected
        // on different scheduler threads while we're closing the connection.
        __atomic_store_n(&conn_res->closed, 1, __ATOMIC_RELEASE);

        // Close with default mode
        dpiConn_close(conn_res->conn, DPI_MODE_CONN_CLOSE_DEFAULT, NULL, 0);
        dpiConn_release(conn_res->conn);
        conn_res->conn = NULL;
    }

    if (conn_res->mutex != NULL) {
        enif_mutex_unlock(conn_res->mutex);
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

    ERL_NIF_TERM release_str = make_binary_string_len(env, releaseString, releaseStringLength);
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
// Statement NIF Functions
// ============================================================

// Prepare a SQL statement
// stmt_prepare(conn, sql) -> {:ok, stmt} | {:error, reason}
static ERL_NIF_TERM nif_stmt_prepare(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 2) {
        return enif_make_badarg(env);
    }

    InexoraConnection *conn_res;
    if (!enif_get_resource(env, argv[0], CONNECTION_RESOURCE_TYPE, (void **)&conn_res)) {
        return make_error_tuple(env, "invalid_connection");
    }

    if (conn_res->conn == NULL) {
        return make_error_tuple(env, "connection_closed");
    }

    ErlNifBinary sql_bin;
    if (!enif_inspect_binary(env, argv[1], &sql_bin)) {
        return make_error_tuple(env, "invalid_sql");
    }

    dpiStmt *stmt = NULL;
    if (dpiConn_prepareStmt(conn_res->conn, 0, (const char *)sql_bin.data, sql_bin.size,
            NULL, 0, &stmt) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(conn_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    InexoraStatement *stmt_res = enif_alloc_resource(STATEMENT_RESOURCE_TYPE, sizeof(InexoraStatement));
    // Keep a reference to the connection resource to prevent use-after-free
    enif_keep_resource(conn_res);
    stmt_res->conn_resource = conn_res;
    stmt_res->context = conn_res->context;
    stmt_res->conn = conn_res->conn;
    stmt_res->stmt = stmt;

    ERL_NIF_TERM result = enif_make_resource(env, stmt_res);
    enif_release_resource(stmt_res);

    return make_ok_tuple(env, result);
}

// Execute a prepared statement
// stmt_execute(stmt) -> {:ok, num_columns} | {:error, reason}
static ERL_NIF_TERM nif_stmt_execute(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 1) {
        return enif_make_badarg(env);
    }

    InexoraStatement *stmt_res;
    if (!enif_get_resource(env, argv[0], STATEMENT_RESOURCE_TYPE, (void **)&stmt_res)) {
        return make_error_tuple(env, "invalid_statement");
    }

    if (stmt_res->stmt == NULL) {
        return make_error_tuple(env, "statement_closed");
    }

    uint32_t numQueryColumns = 0;
    if (dpiStmt_execute(stmt_res->stmt, DPI_MODE_EXEC_DEFAULT, &numQueryColumns) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(stmt_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    return make_ok_tuple(env, enif_make_uint(env, numQueryColumns));
}

// Fetch next row from a SELECT statement
// stmt_fetch(stmt) -> {:ok, true} | {:ok, :done} | {:error, reason}
static ERL_NIF_TERM nif_stmt_fetch(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 1) {
        return enif_make_badarg(env);
    }

    InexoraStatement *stmt_res;
    if (!enif_get_resource(env, argv[0], STATEMENT_RESOURCE_TYPE, (void **)&stmt_res)) {
        return make_error_tuple(env, "invalid_statement");
    }

    if (stmt_res->stmt == NULL) {
        return make_error_tuple(env, "statement_closed");
    }

    int found = 0;
    uint32_t bufferRowIndex = 0;
    if (dpiStmt_fetch(stmt_res->stmt, &found, &bufferRowIndex) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(stmt_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    if (found) {
        return make_ok_tuple(env, ATOM_TRUE);
    } else {
        return make_ok_tuple(env, ATOM_DONE);
    }
}

// Get column metadata for a query
// stmt_get_query_info(stmt, pos) -> {:ok, %{name: name, type: type, ...}} | {:error, reason}
static ERL_NIF_TERM nif_stmt_get_query_info(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 2) {
        return enif_make_badarg(env);
    }

    InexoraStatement *stmt_res;
    if (!enif_get_resource(env, argv[0], STATEMENT_RESOURCE_TYPE, (void **)&stmt_res)) {
        return make_error_tuple(env, "invalid_statement");
    }

    if (stmt_res->stmt == NULL) {
        return make_error_tuple(env, "statement_closed");
    }

    unsigned int pos;
    if (!enif_get_uint(env, argv[1], &pos)) {
        return make_error_tuple(env, "invalid_position");
    }

    dpiQueryInfo queryInfo;
    if (dpiStmt_getQueryInfo(stmt_res->stmt, pos, &queryInfo) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(stmt_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    // Build result map with column info
    ERL_NIF_TERM keys[] = {
        enif_make_atom(env, "name"),
        enif_make_atom(env, "oracle_type"),
        enif_make_atom(env, "native_type"),
        enif_make_atom(env, "db_size"),
        enif_make_atom(env, "client_size"),
        enif_make_atom(env, "precision"),
        enif_make_atom(env, "scale"),
        enif_make_atom(env, "null_ok")
    };
    // Create binary for column name (not charlist)
    ERL_NIF_TERM name_binary;
    unsigned char *name_buf = enif_make_new_binary(env, queryInfo.nameLength, &name_binary);
    memcpy(name_buf, queryInfo.name, queryInfo.nameLength);

    ERL_NIF_TERM values[] = {
        name_binary,
        enif_make_uint(env, queryInfo.typeInfo.oracleTypeNum),
        enif_make_uint(env, queryInfo.typeInfo.defaultNativeTypeNum),
        enif_make_uint(env, queryInfo.typeInfo.dbSizeInBytes),
        enif_make_uint(env, queryInfo.typeInfo.clientSizeInBytes),
        enif_make_int(env, queryInfo.typeInfo.precision),
        enif_make_int(env, queryInfo.typeInfo.scale),
        queryInfo.nullOk ? ATOM_TRUE : ATOM_FALSE
    };

    ERL_NIF_TERM result_map;
    enif_make_map_from_arrays(env, keys, values, 8, &result_map);

    return make_ok_tuple(env, result_map);
}

// Get column value at position for current row
// stmt_get_query_value(stmt, pos) -> {:ok, value} | {:error, reason}
static ERL_NIF_TERM nif_stmt_get_query_value(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 2) {
        return enif_make_badarg(env);
    }

    InexoraStatement *stmt_res;
    if (!enif_get_resource(env, argv[0], STATEMENT_RESOURCE_TYPE, (void **)&stmt_res)) {
        return make_error_tuple(env, "invalid_statement");
    }

    if (stmt_res->stmt == NULL) {
        return make_error_tuple(env, "statement_closed");
    }

    unsigned int pos;
    if (!enif_get_uint(env, argv[1], &pos)) {
        return make_error_tuple(env, "invalid_position");
    }

    dpiNativeTypeNum nativeTypeNum;
    dpiData *data;
    if (dpiStmt_getQueryValue(stmt_res->stmt, pos, &nativeTypeNum, &data) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(stmt_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    // Handle NULL
    if (data->isNull) {
        return make_ok_tuple(env, ATOM_NIL);
    }

    // Convert based on native type
    ERL_NIF_TERM value;
    switch (nativeTypeNum) {
        case DPI_NATIVE_TYPE_INT64:
            value = enif_make_int64(env, data->value.asInt64);
            break;
        case DPI_NATIVE_TYPE_UINT64:
            value = enif_make_uint64(env, data->value.asUint64);
            break;
        case DPI_NATIVE_TYPE_FLOAT: {
            // Convert float to string for Decimal precision
            char buf[64];
            int len = snprintf(buf, sizeof(buf), "%.17g", (double)data->value.asFloat);
            ERL_NIF_TERM bin;
            unsigned char *str = enif_make_new_binary(env, len, &bin);
            memcpy(str, buf, len);
            value = bin;
            break;
        }
        case DPI_NATIVE_TYPE_DOUBLE: {
            // Convert double to string for Decimal precision
            // Using %.17g gives maximum precision for doubles
            char buf[64];
            int len = snprintf(buf, sizeof(buf), "%.17g", data->value.asDouble);
            ERL_NIF_TERM bin;
            unsigned char *str = enif_make_new_binary(env, len, &bin);
            memcpy(str, buf, len);
            value = bin;
            break;
        }
        case DPI_NATIVE_TYPE_BYTES: {
            // Return as binary
            ERL_NIF_TERM bin;
            unsigned char *buf = enif_make_new_binary(env, data->value.asBytes.length, &bin);
            memcpy(buf, data->value.asBytes.ptr, data->value.asBytes.length);
            value = bin;
            break;
        }
        case DPI_NATIVE_TYPE_TIMESTAMP: {
            // Return as tuple {year, month, day, hour, minute, second, fsecond}
            dpiTimestamp *ts = &data->value.asTimestamp;
            value = enif_make_tuple7(env,
                enif_make_int(env, ts->year),
                enif_make_uint(env, ts->month),
                enif_make_uint(env, ts->day),
                enif_make_uint(env, ts->hour),
                enif_make_uint(env, ts->minute),
                enif_make_uint(env, ts->second),
                enif_make_uint(env, ts->fsecond)
            );
            break;
        }
        case DPI_NATIVE_TYPE_BOOLEAN:
            value = data->value.asBoolean ? ATOM_TRUE : ATOM_FALSE;
            break;
        case DPI_NATIVE_TYPE_LOB: {
            // Handle CLOB and BLOB types
            dpiLob *lob = data->value.asLOB;
            if (lob == NULL) {
                value = ATOM_NIL;
                break;
            }

            // Get the size of the LOB
            uint64_t lob_size;
            if (dpiLob_getSize(lob, &lob_size) < 0) {
                dpiErrorInfo errorInfo;
                dpiContext_getError(stmt_res->context, &errorInfo);
                return make_dpi_error(env, &errorInfo);
            }

            // Handle empty LOB
            if (lob_size == 0) {
                ERL_NIF_TERM empty_bin;
                enif_make_new_binary(env, 0, &empty_bin);
                value = empty_bin;
                break;
            }

            // For CLOB, get buffer size (characters to bytes)
            dpiOracleTypeNum lob_type;
            if (dpiLob_getType(lob, &lob_type) < 0) {
                dpiErrorInfo errorInfo;
                dpiContext_getError(stmt_res->context, &errorInfo);
                return make_dpi_error(env, &errorInfo);
            }

            uint64_t buffer_size;
            if (lob_type == DPI_ORACLE_TYPE_CLOB || lob_type == DPI_ORACLE_TYPE_NCLOB) {
                // For CLOBs, get the buffer size in bytes
                if (dpiLob_getBufferSize(lob, lob_size, &buffer_size) < 0) {
                    dpiErrorInfo errorInfo;
                    dpiContext_getError(stmt_res->context, &errorInfo);
                    return make_dpi_error(env, &errorInfo);
                }
            } else {
                // For BLOBs, size is already in bytes
                buffer_size = lob_size;
            }

            // Allocate buffer and read the LOB content
            ERL_NIF_TERM bin;
            unsigned char *buf = enif_make_new_binary(env, buffer_size, &bin);
            uint64_t bytes_read = buffer_size;

            if (dpiLob_readBytes(lob, 1, lob_size, (char *)buf, &bytes_read) < 0) {
                dpiErrorInfo errorInfo;
                dpiContext_getError(stmt_res->context, &errorInfo);
                return make_dpi_error(env, &errorInfo);
            }

            // If we read fewer bytes than allocated, create a correctly sized binary
            if (bytes_read < buffer_size) {
                ERL_NIF_TERM trimmed_bin;
                unsigned char *trimmed_buf = enif_make_new_binary(env, bytes_read, &trimmed_bin);
                memcpy(trimmed_buf, buf, bytes_read);
                value = trimmed_bin;
            } else {
                value = bin;
            }
            break;
        }
        case DPI_NATIVE_TYPE_INTERVAL_DS: {
            // Return as tuple {:interval_ds, days, hours, minutes, seconds, fseconds}
            dpiIntervalDS *interval = &data->value.asIntervalDS;
            value = enif_make_tuple6(env,
                enif_make_atom(env, "interval_ds"),
                enif_make_int(env, interval->days),
                enif_make_int(env, interval->hours),
                enif_make_int(env, interval->minutes),
                enif_make_int(env, interval->seconds),
                enif_make_int(env, interval->fseconds)
            );
            break;
        }
        case DPI_NATIVE_TYPE_INTERVAL_YM: {
            // Return as tuple {:interval_ym, years, months}
            dpiIntervalYM *interval = &data->value.asIntervalYM;
            value = enif_make_tuple3(env,
                enif_make_atom(env, "interval_ym"),
                enif_make_int(env, interval->years),
                enif_make_int(env, interval->months)
            );
            break;
        }
        case DPI_NATIVE_TYPE_ROWID: {
            // Return ROWID as string
            dpiRowid *rowid = data->value.asRowid;
            const char *rowidStr;
            uint32_t rowidLen;
            if (dpiRowid_getStringValue(rowid, &rowidStr, &rowidLen) < 0) {
                dpiErrorInfo errorInfo;
                dpiContext_getError(stmt_res->context, &errorInfo);
                return make_dpi_error(env, &errorInfo);
            }
            unsigned char *buf = enif_make_new_binary(env, rowidLen, &value);
            memcpy(buf, rowidStr, rowidLen);
            break;
        }
        default:
            // For unsupported types, return raw bytes if possible or nil
            return make_error_tuple(env, "unsupported_type");
    }

    return make_ok_tuple(env, value);
}

// Get row count (for DML statements)
// stmt_get_row_count(stmt) -> {:ok, count} | {:error, reason}
static ERL_NIF_TERM nif_stmt_get_row_count(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 1) {
        return enif_make_badarg(env);
    }

    InexoraStatement *stmt_res;
    if (!enif_get_resource(env, argv[0], STATEMENT_RESOURCE_TYPE, (void **)&stmt_res)) {
        return make_error_tuple(env, "invalid_statement");
    }

    if (stmt_res->stmt == NULL) {
        return make_error_tuple(env, "statement_closed");
    }

    uint64_t count;
    if (dpiStmt_getRowCount(stmt_res->stmt, &count) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(stmt_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    return make_ok_tuple(env, enif_make_uint64(env, count));
}

// Bind value by position
// stmt_bind_value_by_pos(stmt, pos, type_atom, value) -> :ok | {:error, reason}
static ERL_NIF_TERM nif_stmt_bind_value_by_pos(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 4) {
        return enif_make_badarg(env);
    }

    InexoraStatement *stmt_res;
    if (!enif_get_resource(env, argv[0], STATEMENT_RESOURCE_TYPE, (void **)&stmt_res)) {
        return make_error_tuple(env, "invalid_statement");
    }

    if (stmt_res->stmt == NULL) {
        return make_error_tuple(env, "statement_closed");
    }

    unsigned int pos;
    if (!enif_get_uint(env, argv[1], &pos)) {
        return make_error_tuple(env, "invalid_position");
    }

    // Get type atom
    char type_str[32];
    if (!enif_get_atom(env, argv[2], type_str, sizeof(type_str), ERL_NIF_LATIN1)) {
        return make_error_tuple(env, "invalid_type");
    }

    dpiData data;
    dpiNativeTypeNum nativeType;
    memset(&data, 0, sizeof(data));

    // Handle nil/null - need to determine type from hint for proper binding
    if (enif_is_identical(argv[3], ATOM_NIL)) {
        data.isNull = 1;
        // Use appropriate native type based on type hint for NULL values
        if (strcmp(type_str, "raw") == 0) {
            nativeType = DPI_NATIVE_TYPE_BYTES;
        } else if (strcmp(type_str, "string") == 0 || strcmp(type_str, "binary") == 0) {
            nativeType = DPI_NATIVE_TYPE_BYTES;
        } else if (strcmp(type_str, "float") == 0) {
            nativeType = DPI_NATIVE_TYPE_DOUBLE;
        } else {
            nativeType = DPI_NATIVE_TYPE_INT64;
        }
    }
    // Handle based on type hint
    else if (strcmp(type_str, "integer") == 0) {
        ErlNifSInt64 val;
        if (!enif_get_int64(env, argv[3], &val)) {
            return make_error_tuple(env, "invalid_integer_value");
        }
        data.isNull = 0;
        data.value.asInt64 = val;
        nativeType = DPI_NATIVE_TYPE_INT64;
    }
    else if (strcmp(type_str, "float") == 0) {
        double val;
        if (!enif_get_double(env, argv[3], &val)) {
            // Try integer conversion
            ErlNifSInt64 int_val;
            if (enif_get_int64(env, argv[3], &int_val)) {
                val = (double)int_val;
            } else {
                return make_error_tuple(env, "invalid_float_value");
            }
        }
        data.isNull = 0;
        data.value.asDouble = val;
        nativeType = DPI_NATIVE_TYPE_DOUBLE;
    }
    else if (strcmp(type_str, "string") == 0 || strcmp(type_str, "binary") == 0) {
        ErlNifBinary bin;
        if (!enif_inspect_binary(env, argv[3], &bin)) {
            return make_error_tuple(env, "invalid_binary_value");
        }
        data.isNull = 0;
        data.value.asBytes.ptr = (char *)bin.data;
        data.value.asBytes.length = bin.size;
        nativeType = DPI_NATIVE_TYPE_BYTES;
    }
    else if (strcmp(type_str, "raw") == 0) {
        // RAW types need to use dpiStmt_bindByPos with a variable
        // to properly specify DPI_ORACLE_TYPE_RAW
        dpiVar *var;
        dpiData *varData;

        // Check if value is nil (NULL)
        if (enif_is_identical(argv[3], ATOM_NIL)) {
            // Create a variable for NULL RAW
            if (dpiConn_newVar(stmt_res->conn, DPI_ORACLE_TYPE_RAW, DPI_NATIVE_TYPE_BYTES,
                               1, 1, 0, 0, NULL, &var, &varData) < 0) {
                dpiErrorInfo errorInfo;
                dpiContext_getError(stmt_res->context, &errorInfo);
                return make_dpi_error(env, &errorInfo);
            }
            varData->isNull = 1;
        } else {
            ErlNifBinary bin;
            if (!enif_inspect_binary(env, argv[3], &bin)) {
                return make_error_tuple(env, "invalid_binary_value");
            }

            if (dpiConn_newVar(stmt_res->conn, DPI_ORACLE_TYPE_RAW, DPI_NATIVE_TYPE_BYTES,
                               1, bin.size > 0 ? bin.size : 1, 0, 0, NULL, &var, &varData) < 0) {
                dpiErrorInfo errorInfo;
                dpiContext_getError(stmt_res->context, &errorInfo);
                return make_dpi_error(env, &errorInfo);
            }

            // Set the value
            if (dpiVar_setFromBytes(var, 0, (const char *)bin.data, bin.size) < 0) {
                dpiErrorInfo errorInfo;
                dpiContext_getError(stmt_res->context, &errorInfo);
                dpiVar_release(var);
                return make_dpi_error(env, &errorInfo);
            }
        }

        // Bind the variable
        if (dpiStmt_bindByPos(stmt_res->stmt, pos, var) < 0) {
            dpiErrorInfo errorInfo;
            dpiContext_getError(stmt_res->context, &errorInfo);
            dpiVar_release(var);
            return make_dpi_error(env, &errorInfo);
        }

        // Note: We don't release the var here as it needs to stay valid until execute
        // It will be released when the statement is closed
        return ATOM_OK;
    }
    else if (strcmp(type_str, "interval_ds") == 0) {
        // Bind INTERVAL DAY TO SECOND
        // Expect tuple {days, hours, minutes, seconds, fseconds}
        int arity;
        const ERL_NIF_TERM *tuple;
        if (!enif_get_tuple(env, argv[3], &arity, &tuple) || arity != 5) {
            return make_error_tuple(env, "invalid_interval_ds");
        }

        int days, hours, minutes, seconds, fseconds;
        if (!enif_get_int(env, tuple[0], &days) ||
            !enif_get_int(env, tuple[1], &hours) ||
            !enif_get_int(env, tuple[2], &minutes) ||
            !enif_get_int(env, tuple[3], &seconds) ||
            !enif_get_int(env, tuple[4], &fseconds)) {
            return make_error_tuple(env, "invalid_interval_ds_values");
        }

        dpiVar *var;
        dpiData *varData;
        if (dpiConn_newVar(stmt_res->conn, DPI_ORACLE_TYPE_INTERVAL_DS, DPI_NATIVE_TYPE_INTERVAL_DS,
                           1, 0, 0, 0, NULL, &var, &varData) < 0) {
            dpiErrorInfo errorInfo;
            dpiContext_getError(stmt_res->context, &errorInfo);
            return make_dpi_error(env, &errorInfo);
        }

        varData->isNull = 0;
        varData->value.asIntervalDS.days = days;
        varData->value.asIntervalDS.hours = hours;
        varData->value.asIntervalDS.minutes = minutes;
        varData->value.asIntervalDS.seconds = seconds;
        varData->value.asIntervalDS.fseconds = fseconds;

        if (dpiStmt_bindByPos(stmt_res->stmt, pos, var) < 0) {
            dpiErrorInfo errorInfo;
            dpiContext_getError(stmt_res->context, &errorInfo);
            dpiVar_release(var);
            return make_dpi_error(env, &errorInfo);
        }

        return ATOM_OK;
    }
    else if (strcmp(type_str, "interval_ym") == 0) {
        // Bind INTERVAL YEAR TO MONTH
        // Expect tuple {years, months}
        int arity;
        const ERL_NIF_TERM *tuple;
        if (!enif_get_tuple(env, argv[3], &arity, &tuple) || arity != 2) {
            return make_error_tuple(env, "invalid_interval_ym");
        }

        int years, months;
        if (!enif_get_int(env, tuple[0], &years) ||
            !enif_get_int(env, tuple[1], &months)) {
            return make_error_tuple(env, "invalid_interval_ym_values");
        }

        dpiVar *var;
        dpiData *varData;
        if (dpiConn_newVar(stmt_res->conn, DPI_ORACLE_TYPE_INTERVAL_YM, DPI_NATIVE_TYPE_INTERVAL_YM,
                           1, 0, 0, 0, NULL, &var, &varData) < 0) {
            dpiErrorInfo errorInfo;
            dpiContext_getError(stmt_res->context, &errorInfo);
            return make_dpi_error(env, &errorInfo);
        }

        varData->isNull = 0;
        varData->value.asIntervalYM.years = years;
        varData->value.asIntervalYM.months = months;

        if (dpiStmt_bindByPos(stmt_res->stmt, pos, var) < 0) {
            dpiErrorInfo errorInfo;
            dpiContext_getError(stmt_res->context, &errorInfo);
            dpiVar_release(var);
            return make_dpi_error(env, &errorInfo);
        }

        return ATOM_OK;
    }
    else {
        return make_error_tuple(env, "unsupported_bind_type");
    }

    if (dpiStmt_bindValueByPos(stmt_res->stmt, pos, nativeType, &data) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(stmt_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    return ATOM_OK;
}

// Bind value by name
// stmt_bind_value_by_name(stmt, name, type_atom, value) -> :ok | {:error, reason}
static ERL_NIF_TERM nif_stmt_bind_value_by_name(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 4) {
        return enif_make_badarg(env);
    }

    InexoraStatement *stmt_res;
    if (!enif_get_resource(env, argv[0], STATEMENT_RESOURCE_TYPE, (void **)&stmt_res)) {
        return make_error_tuple(env, "invalid_statement");
    }

    if (stmt_res->stmt == NULL) {
        return make_error_tuple(env, "statement_closed");
    }

    // Get parameter name as binary
    ErlNifBinary name_bin;
    if (!enif_inspect_binary(env, argv[1], &name_bin)) {
        return make_error_tuple(env, "invalid_name");
    }

    // Get type atom
    char type_str[32];
    if (!enif_get_atom(env, argv[2], type_str, sizeof(type_str), ERL_NIF_LATIN1)) {
        return make_error_tuple(env, "invalid_type");
    }

    dpiData data;
    dpiNativeTypeNum nativeType;
    memset(&data, 0, sizeof(data));

    // Handle nil/null - need to determine type from hint for proper binding
    if (enif_is_identical(argv[3], ATOM_NIL)) {
        data.isNull = 1;
        // Use appropriate native type based on type hint for NULL values
        if (strcmp(type_str, "raw") == 0) {
            nativeType = DPI_NATIVE_TYPE_BYTES;
        } else if (strcmp(type_str, "string") == 0 || strcmp(type_str, "binary") == 0) {
            nativeType = DPI_NATIVE_TYPE_BYTES;
        } else if (strcmp(type_str, "float") == 0) {
            nativeType = DPI_NATIVE_TYPE_DOUBLE;
        } else {
            nativeType = DPI_NATIVE_TYPE_INT64;
        }
    }
    // Handle based on type hint
    else if (strcmp(type_str, "integer") == 0) {
        ErlNifSInt64 val;
        if (!enif_get_int64(env, argv[3], &val)) {
            return make_error_tuple(env, "invalid_integer_value");
        }
        data.isNull = 0;
        data.value.asInt64 = val;
        nativeType = DPI_NATIVE_TYPE_INT64;
    }
    else if (strcmp(type_str, "float") == 0) {
        double val;
        if (!enif_get_double(env, argv[3], &val)) {
            // Try integer conversion
            ErlNifSInt64 int_val;
            if (enif_get_int64(env, argv[3], &int_val)) {
                val = (double)int_val;
            } else {
                return make_error_tuple(env, "invalid_float_value");
            }
        }
        data.isNull = 0;
        data.value.asDouble = val;
        nativeType = DPI_NATIVE_TYPE_DOUBLE;
    }
    else if (strcmp(type_str, "string") == 0 || strcmp(type_str, "binary") == 0) {
        ErlNifBinary bin;
        if (!enif_inspect_binary(env, argv[3], &bin)) {
            return make_error_tuple(env, "invalid_binary_value");
        }
        data.isNull = 0;
        data.value.asBytes.ptr = (char *)bin.data;
        data.value.asBytes.length = bin.size;
        nativeType = DPI_NATIVE_TYPE_BYTES;
    }
    else if (strcmp(type_str, "raw") == 0) {
        // RAW types need to use dpiStmt_bindByName with a variable
        // to properly specify DPI_ORACLE_TYPE_RAW
        dpiVar *var;
        dpiData *varData;

        // Check if value is nil (NULL)
        if (enif_is_identical(argv[3], ATOM_NIL)) {
            // Create a variable for NULL RAW
            if (dpiConn_newVar(stmt_res->conn, DPI_ORACLE_TYPE_RAW, DPI_NATIVE_TYPE_BYTES,
                               1, 1, 0, 0, NULL, &var, &varData) < 0) {
                dpiErrorInfo errorInfo;
                dpiContext_getError(stmt_res->context, &errorInfo);
                return make_dpi_error(env, &errorInfo);
            }
            varData->isNull = 1;
        } else {
            ErlNifBinary bin;
            if (!enif_inspect_binary(env, argv[3], &bin)) {
                return make_error_tuple(env, "invalid_binary_value");
            }

            if (dpiConn_newVar(stmt_res->conn, DPI_ORACLE_TYPE_RAW, DPI_NATIVE_TYPE_BYTES,
                               1, bin.size > 0 ? bin.size : 1, 0, 0, NULL, &var, &varData) < 0) {
                dpiErrorInfo errorInfo;
                dpiContext_getError(stmt_res->context, &errorInfo);
                return make_dpi_error(env, &errorInfo);
            }

            // Set the value
            if (dpiVar_setFromBytes(var, 0, (const char *)bin.data, bin.size) < 0) {
                dpiErrorInfo errorInfo;
                dpiContext_getError(stmt_res->context, &errorInfo);
                dpiVar_release(var);
                return make_dpi_error(env, &errorInfo);
            }
        }

        // Bind the variable by name
        if (dpiStmt_bindByName(stmt_res->stmt, (const char *)name_bin.data, name_bin.size, var) < 0) {
            dpiErrorInfo errorInfo;
            dpiContext_getError(stmt_res->context, &errorInfo);
            dpiVar_release(var);
            return make_dpi_error(env, &errorInfo);
        }

        return ATOM_OK;
    }
    else if (strcmp(type_str, "interval_ds") == 0) {
        // Bind INTERVAL DAY TO SECOND
        // Expect tuple {days, hours, minutes, seconds, fseconds}
        int arity;
        const ERL_NIF_TERM *tuple;
        if (!enif_get_tuple(env, argv[3], &arity, &tuple) || arity != 5) {
            return make_error_tuple(env, "invalid_interval_ds");
        }

        int days, hours, minutes, seconds, fseconds;
        if (!enif_get_int(env, tuple[0], &days) ||
            !enif_get_int(env, tuple[1], &hours) ||
            !enif_get_int(env, tuple[2], &minutes) ||
            !enif_get_int(env, tuple[3], &seconds) ||
            !enif_get_int(env, tuple[4], &fseconds)) {
            return make_error_tuple(env, "invalid_interval_ds_values");
        }

        dpiVar *var;
        dpiData *varData;
        if (dpiConn_newVar(stmt_res->conn, DPI_ORACLE_TYPE_INTERVAL_DS, DPI_NATIVE_TYPE_INTERVAL_DS,
                           1, 0, 0, 0, NULL, &var, &varData) < 0) {
            dpiErrorInfo errorInfo;
            dpiContext_getError(stmt_res->context, &errorInfo);
            return make_dpi_error(env, &errorInfo);
        }

        varData->isNull = 0;
        varData->value.asIntervalDS.days = days;
        varData->value.asIntervalDS.hours = hours;
        varData->value.asIntervalDS.minutes = minutes;
        varData->value.asIntervalDS.seconds = seconds;
        varData->value.asIntervalDS.fseconds = fseconds;

        if (dpiStmt_bindByName(stmt_res->stmt, (const char *)name_bin.data, name_bin.size, var) < 0) {
            dpiErrorInfo errorInfo;
            dpiContext_getError(stmt_res->context, &errorInfo);
            dpiVar_release(var);
            return make_dpi_error(env, &errorInfo);
        }

        return ATOM_OK;
    }
    else if (strcmp(type_str, "interval_ym") == 0) {
        // Bind INTERVAL YEAR TO MONTH
        // Expect tuple {years, months}
        int arity;
        const ERL_NIF_TERM *tuple;
        if (!enif_get_tuple(env, argv[3], &arity, &tuple) || arity != 2) {
            return make_error_tuple(env, "invalid_interval_ym");
        }

        int years, months;
        if (!enif_get_int(env, tuple[0], &years) ||
            !enif_get_int(env, tuple[1], &months)) {
            return make_error_tuple(env, "invalid_interval_ym_values");
        }

        dpiVar *var;
        dpiData *varData;
        if (dpiConn_newVar(stmt_res->conn, DPI_ORACLE_TYPE_INTERVAL_YM, DPI_NATIVE_TYPE_INTERVAL_YM,
                           1, 0, 0, 0, NULL, &var, &varData) < 0) {
            dpiErrorInfo errorInfo;
            dpiContext_getError(stmt_res->context, &errorInfo);
            return make_dpi_error(env, &errorInfo);
        }

        varData->isNull = 0;
        varData->value.asIntervalYM.years = years;
        varData->value.asIntervalYM.months = months;

        if (dpiStmt_bindByName(stmt_res->stmt, (const char *)name_bin.data, name_bin.size, var) < 0) {
            dpiErrorInfo errorInfo;
            dpiContext_getError(stmt_res->context, &errorInfo);
            dpiVar_release(var);
            return make_dpi_error(env, &errorInfo);
        }

        return ATOM_OK;
    }
    else {
        return make_error_tuple(env, "unsupported_bind_type");
    }

    if (dpiStmt_bindValueByName(stmt_res->stmt, (const char *)name_bin.data, name_bin.size, nativeType, &data) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(stmt_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    return ATOM_OK;
}

// Get bind names from a prepared statement
// stmt_get_bind_names(stmt) -> {:ok, [name1, name2, ...]} | {:error, reason}
static ERL_NIF_TERM nif_stmt_get_bind_names(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 1) {
        return enif_make_badarg(env);
    }

    InexoraStatement *stmt_res;
    if (!enif_get_resource(env, argv[0], STATEMENT_RESOURCE_TYPE, (void **)&stmt_res)) {
        return make_error_tuple(env, "invalid_statement");
    }

    if (stmt_res->stmt == NULL) {
        return make_error_tuple(env, "statement_closed");
    }

    // Get bind count first
    uint32_t bindCount;
    if (dpiStmt_getBindCount(stmt_res->stmt, &bindCount) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(stmt_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    if (bindCount == 0) {
        return make_ok_tuple(env, enif_make_list(env, 0));
    }

    // Allocate arrays for bind names
    const char **names = enif_alloc(sizeof(const char *) * bindCount);
    uint32_t *nameLengths = enif_alloc(sizeof(uint32_t) * bindCount);

    if (names == NULL || nameLengths == NULL) {
        if (names) enif_free(names);
        if (nameLengths) enif_free(nameLengths);
        return make_error_tuple(env, "allocation_failed");
    }

    uint32_t numNames = bindCount;
    if (dpiStmt_getBindNames(stmt_res->stmt, &numNames, names, nameLengths) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(stmt_res->context, &errorInfo);
        enif_free(names);
        enif_free(nameLengths);
        return make_dpi_error(env, &errorInfo);
    }

    // Build list of name binaries
    ERL_NIF_TERM *name_terms = enif_alloc(sizeof(ERL_NIF_TERM) * numNames);
    if (name_terms == NULL) {
        enif_free(names);
        enif_free(nameLengths);
        return make_error_tuple(env, "allocation_failed");
    }

    for (uint32_t i = 0; i < numNames; i++) {
        ERL_NIF_TERM name_bin;
        unsigned char *buf = enif_make_new_binary(env, nameLengths[i], &name_bin);
        memcpy(buf, names[i], nameLengths[i]);
        name_terms[i] = name_bin;
    }

    ERL_NIF_TERM result_list = enif_make_list_from_array(env, name_terms, numNames);

    enif_free(names);
    enif_free(nameLengths);
    enif_free(name_terms);

    return make_ok_tuple(env, result_list);
}

// Close/release a statement
// stmt_close(stmt) -> :ok | {:error, reason}
static ERL_NIF_TERM nif_stmt_close(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 1) {
        return enif_make_badarg(env);
    }

    InexoraStatement *stmt_res;
    if (!enif_get_resource(env, argv[0], STATEMENT_RESOURCE_TYPE, (void **)&stmt_res)) {
        return make_error_tuple(env, "invalid_statement");
    }

    if (stmt_res->stmt != NULL) {
        dpiStmt_release(stmt_res->stmt);
        stmt_res->stmt = NULL;
    }

    return ATOM_OK;
}

// Define a column to be fetched as bytes (for NUMBER precision)
// stmt_define_as_bytes(stmt, pos, max_size) -> :ok | {:error, reason}
static ERL_NIF_TERM nif_stmt_define_as_bytes(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 3) {
        return enif_make_badarg(env);
    }

    InexoraStatement *stmt_res;
    if (!enif_get_resource(env, argv[0], STATEMENT_RESOURCE_TYPE, (void **)&stmt_res)) {
        return make_error_tuple(env, "invalid_statement");
    }

    if (stmt_res->stmt == NULL) {
        return make_error_tuple(env, "statement_closed");
    }

    unsigned int pos;
    if (!enif_get_uint(env, argv[1], &pos)) {
        return make_error_tuple(env, "invalid_position");
    }

    unsigned int max_size;
    if (!enif_get_uint(env, argv[2], &max_size)) {
        return make_error_tuple(env, "invalid_max_size");
    }

    // Create a variable to fetch NUMBER as bytes (string)
    dpiVar *var;
    dpiData *data;
    if (dpiConn_newVar(stmt_res->conn, DPI_ORACLE_TYPE_NUMBER, DPI_NATIVE_TYPE_BYTES,
                       1, max_size, 0, 0, NULL, &var, &data) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(stmt_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    // Define the column to use this variable
    if (dpiStmt_define(stmt_res->stmt, pos, var) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(stmt_res->context, &errorInfo);
        dpiVar_release(var);
        return make_dpi_error(env, &errorInfo);
    }

    // Note: The variable is now owned by the statement and will be released when
    // the statement is closed. We don't need to track it separately.

    return ATOM_OK;
}

// ============================================================
// Variable NIF Functions (for batch/array operations)
// ============================================================

// Create a new variable for array/batch operations
// conn_new_var(conn, oracle_type, native_type, max_array_size, size) -> {:ok, var} | {:error, reason}
// oracle_type: atom (:varchar, :number, :raw, :date, :timestamp, :clob, :blob, etc.)
// native_type: atom (:bytes, :int64, :uint64, :double, :float, :timestamp, etc.)
static ERL_NIF_TERM nif_conn_new_var(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 5) {
        return enif_make_badarg(env);
    }

    InexoraConnection *conn_res;
    if (!enif_get_resource(env, argv[0], CONNECTION_RESOURCE_TYPE, (void **)&conn_res)) {
        return make_error_tuple(env, "invalid_connection");
    }

    if (conn_res->conn == NULL) {
        return make_error_tuple(env, "connection_closed");
    }

    // Get oracle_type atom
    char oracle_type_str[64];
    if (!enif_get_atom(env, argv[1], oracle_type_str, sizeof(oracle_type_str), ERL_NIF_LATIN1)) {
        return make_error_tuple(env, "invalid_oracle_type");
    }

    // Get native_type atom
    char native_type_str[64];
    if (!enif_get_atom(env, argv[2], native_type_str, sizeof(native_type_str), ERL_NIF_LATIN1)) {
        return make_error_tuple(env, "invalid_native_type");
    }

    unsigned int max_array_size;
    if (!enif_get_uint(env, argv[3], &max_array_size) || max_array_size == 0) {
        return make_error_tuple(env, "invalid_max_array_size");
    }

    unsigned int size;
    if (!enif_get_uint(env, argv[4], &size)) {
        return make_error_tuple(env, "invalid_size");
    }

    // Map oracle_type atom to dpiOracleTypeNum
    dpiOracleTypeNum oracleTypeNum;
    if (strcmp(oracle_type_str, "varchar") == 0) {
        oracleTypeNum = DPI_ORACLE_TYPE_VARCHAR;
    } else if (strcmp(oracle_type_str, "nvarchar") == 0) {
        oracleTypeNum = DPI_ORACLE_TYPE_NVARCHAR;
    } else if (strcmp(oracle_type_str, "char") == 0) {
        oracleTypeNum = DPI_ORACLE_TYPE_CHAR;
    } else if (strcmp(oracle_type_str, "nchar") == 0) {
        oracleTypeNum = DPI_ORACLE_TYPE_NCHAR;
    } else if (strcmp(oracle_type_str, "number") == 0) {
        oracleTypeNum = DPI_ORACLE_TYPE_NUMBER;
    } else if (strcmp(oracle_type_str, "native_int") == 0) {
        oracleTypeNum = DPI_ORACLE_TYPE_NATIVE_INT;
    } else if (strcmp(oracle_type_str, "native_uint") == 0) {
        oracleTypeNum = DPI_ORACLE_TYPE_NATIVE_UINT;
    } else if (strcmp(oracle_type_str, "native_float") == 0) {
        oracleTypeNum = DPI_ORACLE_TYPE_NATIVE_FLOAT;
    } else if (strcmp(oracle_type_str, "native_double") == 0) {
        oracleTypeNum = DPI_ORACLE_TYPE_NATIVE_DOUBLE;
    } else if (strcmp(oracle_type_str, "date") == 0) {
        oracleTypeNum = DPI_ORACLE_TYPE_DATE;
    } else if (strcmp(oracle_type_str, "timestamp") == 0) {
        oracleTypeNum = DPI_ORACLE_TYPE_TIMESTAMP;
    } else if (strcmp(oracle_type_str, "timestamp_tz") == 0) {
        oracleTypeNum = DPI_ORACLE_TYPE_TIMESTAMP_TZ;
    } else if (strcmp(oracle_type_str, "timestamp_ltz") == 0) {
        oracleTypeNum = DPI_ORACLE_TYPE_TIMESTAMP_LTZ;
    } else if (strcmp(oracle_type_str, "raw") == 0) {
        oracleTypeNum = DPI_ORACLE_TYPE_RAW;
    } else if (strcmp(oracle_type_str, "long_raw") == 0) {
        oracleTypeNum = DPI_ORACLE_TYPE_LONG_RAW;
    } else if (strcmp(oracle_type_str, "clob") == 0) {
        oracleTypeNum = DPI_ORACLE_TYPE_CLOB;
    } else if (strcmp(oracle_type_str, "nclob") == 0) {
        oracleTypeNum = DPI_ORACLE_TYPE_NCLOB;
    } else if (strcmp(oracle_type_str, "blob") == 0) {
        oracleTypeNum = DPI_ORACLE_TYPE_BLOB;
    } else if (strcmp(oracle_type_str, "rowid") == 0) {
        oracleTypeNum = DPI_ORACLE_TYPE_ROWID;
    } else if (strcmp(oracle_type_str, "interval_ds") == 0) {
        oracleTypeNum = DPI_ORACLE_TYPE_INTERVAL_DS;
    } else if (strcmp(oracle_type_str, "interval_ym") == 0) {
        oracleTypeNum = DPI_ORACLE_TYPE_INTERVAL_YM;
    } else {
        return make_error_tuple(env, "unsupported_oracle_type");
    }

    // Map native_type atom to dpiNativeTypeNum
    dpiNativeTypeNum nativeTypeNum;
    if (strcmp(native_type_str, "bytes") == 0) {
        nativeTypeNum = DPI_NATIVE_TYPE_BYTES;
    } else if (strcmp(native_type_str, "int64") == 0) {
        nativeTypeNum = DPI_NATIVE_TYPE_INT64;
    } else if (strcmp(native_type_str, "uint64") == 0) {
        nativeTypeNum = DPI_NATIVE_TYPE_UINT64;
    } else if (strcmp(native_type_str, "float") == 0) {
        nativeTypeNum = DPI_NATIVE_TYPE_FLOAT;
    } else if (strcmp(native_type_str, "double") == 0) {
        nativeTypeNum = DPI_NATIVE_TYPE_DOUBLE;
    } else if (strcmp(native_type_str, "timestamp") == 0) {
        nativeTypeNum = DPI_NATIVE_TYPE_TIMESTAMP;
    } else if (strcmp(native_type_str, "interval_ds") == 0) {
        nativeTypeNum = DPI_NATIVE_TYPE_INTERVAL_DS;
    } else if (strcmp(native_type_str, "interval_ym") == 0) {
        nativeTypeNum = DPI_NATIVE_TYPE_INTERVAL_YM;
    } else if (strcmp(native_type_str, "lob") == 0) {
        nativeTypeNum = DPI_NATIVE_TYPE_LOB;
    } else if (strcmp(native_type_str, "rowid") == 0) {
        nativeTypeNum = DPI_NATIVE_TYPE_ROWID;
    } else {
        return make_error_tuple(env, "unsupported_native_type");
    }

    dpiVar *var;
    dpiData *data;
    if (dpiConn_newVar(conn_res->conn, oracleTypeNum, nativeTypeNum,
                       max_array_size, size, 0, 0, NULL, &var, &data) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(conn_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    // Wrap variable in Erlang resource
    InexoraVariable *var_res = enif_alloc_resource(VARIABLE_RESOURCE_TYPE, sizeof(InexoraVariable));
    // Keep a reference to the connection resource to prevent use-after-free
    enif_keep_resource(conn_res);
    var_res->conn_resource = conn_res;
    var_res->context = conn_res->context;
    var_res->conn = conn_res->conn;
    var_res->var = var;
    var_res->data = data;
    var_res->maxArraySize = max_array_size;
    var_res->oracleTypeNum = oracleTypeNum;
    var_res->nativeTypeNum = nativeTypeNum;

    ERL_NIF_TERM result = enif_make_resource(env, var_res);
    enif_release_resource(var_res);

    return make_ok_tuple(env, result);
}

// Set the number of elements in the array
// var_set_num_elements(var, num_elements) -> :ok | {:error, reason}
static ERL_NIF_TERM nif_var_set_num_elements(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 2) {
        return enif_make_badarg(env);
    }

    InexoraVariable *var_res;
    if (!enif_get_resource(env, argv[0], VARIABLE_RESOURCE_TYPE, (void **)&var_res)) {
        return make_error_tuple(env, "invalid_variable");
    }

    if (var_res->var == NULL) {
        return make_error_tuple(env, "variable_released");
    }

    unsigned int num_elements;
    if (!enif_get_uint(env, argv[1], &num_elements)) {
        return make_error_tuple(env, "invalid_num_elements");
    }

    if (num_elements > var_res->maxArraySize) {
        return make_error_tuple(env, "num_elements_exceeds_max_array_size");
    }

    if (dpiVar_setNumElementsInArray(var_res->var, num_elements) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(var_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    return ATOM_OK;
}

// Get the number of elements in the array
// var_get_num_elements(var) -> {:ok, num_elements} | {:error, reason}
static ERL_NIF_TERM nif_var_get_num_elements(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 1) {
        return enif_make_badarg(env);
    }

    InexoraVariable *var_res;
    if (!enif_get_resource(env, argv[0], VARIABLE_RESOURCE_TYPE, (void **)&var_res)) {
        return make_error_tuple(env, "invalid_variable");
    }

    if (var_res->var == NULL) {
        return make_error_tuple(env, "variable_released");
    }

    uint32_t num_elements;
    if (dpiVar_getNumElementsInArray(var_res->var, &num_elements) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(var_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    return make_ok_tuple(env, enif_make_uint(env, num_elements));
}

// Set bytes value at array position
// var_set_from_bytes(var, pos, value) -> :ok | {:error, reason}
static ERL_NIF_TERM nif_var_set_from_bytes(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 3) {
        return enif_make_badarg(env);
    }

    InexoraVariable *var_res;
    if (!enif_get_resource(env, argv[0], VARIABLE_RESOURCE_TYPE, (void **)&var_res)) {
        return make_error_tuple(env, "invalid_variable");
    }

    if (var_res->var == NULL) {
        return make_error_tuple(env, "variable_released");
    }

    unsigned int pos;
    if (!enif_get_uint(env, argv[1], &pos)) {
        return make_error_tuple(env, "invalid_position");
    }

    if (pos >= var_res->maxArraySize) {
        return make_error_tuple(env, "position_out_of_bounds");
    }

    ErlNifBinary bin;
    if (!enif_inspect_binary(env, argv[2], &bin)) {
        return make_error_tuple(env, "invalid_binary_value");
    }

    if (dpiVar_setFromBytes(var_res->var, pos, (const char *)bin.data, bin.size) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(var_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    return ATOM_OK;
}

// Set integer value at array position
// var_set_from_int(var, pos, value) -> :ok | {:error, reason}
static ERL_NIF_TERM nif_var_set_from_int(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 3) {
        return enif_make_badarg(env);
    }

    InexoraVariable *var_res;
    if (!enif_get_resource(env, argv[0], VARIABLE_RESOURCE_TYPE, (void **)&var_res)) {
        return make_error_tuple(env, "invalid_variable");
    }

    if (var_res->var == NULL) {
        return make_error_tuple(env, "variable_released");
    }

    unsigned int pos;
    if (!enif_get_uint(env, argv[1], &pos)) {
        return make_error_tuple(env, "invalid_position");
    }

    if (pos >= var_res->maxArraySize) {
        return make_error_tuple(env, "position_out_of_bounds");
    }

    ErlNifSInt64 value;
    if (!enif_get_int64(env, argv[2], &value)) {
        return make_error_tuple(env, "invalid_integer_value");
    }

    // Set directly in the data array
    var_res->data[pos].isNull = 0;
    var_res->data[pos].value.asInt64 = value;

    return ATOM_OK;
}

// Set double value at array position
// var_set_from_double(var, pos, value) -> :ok | {:error, reason}
static ERL_NIF_TERM nif_var_set_from_double(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 3) {
        return enif_make_badarg(env);
    }

    InexoraVariable *var_res;
    if (!enif_get_resource(env, argv[0], VARIABLE_RESOURCE_TYPE, (void **)&var_res)) {
        return make_error_tuple(env, "invalid_variable");
    }

    if (var_res->var == NULL) {
        return make_error_tuple(env, "variable_released");
    }

    unsigned int pos;
    if (!enif_get_uint(env, argv[1], &pos)) {
        return make_error_tuple(env, "invalid_position");
    }

    if (pos >= var_res->maxArraySize) {
        return make_error_tuple(env, "position_out_of_bounds");
    }

    double value;
    if (!enif_get_double(env, argv[2], &value)) {
        // Try integer conversion
        ErlNifSInt64 int_val;
        if (enif_get_int64(env, argv[2], &int_val)) {
            value = (double)int_val;
        } else {
            return make_error_tuple(env, "invalid_double_value");
        }
    }

    // Set directly in the data array
    var_res->data[pos].isNull = 0;
    var_res->data[pos].value.asDouble = value;

    return ATOM_OK;
}

// Set NULL at array position
// var_set_null(var, pos) -> :ok | {:error, reason}
static ERL_NIF_TERM nif_var_set_null(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 2) {
        return enif_make_badarg(env);
    }

    InexoraVariable *var_res;
    if (!enif_get_resource(env, argv[0], VARIABLE_RESOURCE_TYPE, (void **)&var_res)) {
        return make_error_tuple(env, "invalid_variable");
    }

    if (var_res->var == NULL) {
        return make_error_tuple(env, "variable_released");
    }

    unsigned int pos;
    if (!enif_get_uint(env, argv[1], &pos)) {
        return make_error_tuple(env, "invalid_position");
    }

    if (pos >= var_res->maxArraySize) {
        return make_error_tuple(env, "position_out_of_bounds");
    }

    // Set null flag in the data array
    var_res->data[pos].isNull = 1;

    return ATOM_OK;
}

// Helper function to convert dpiData to Erlang term
static ERL_NIF_TERM data_to_term(ErlNifEnv *env, dpiData *data, dpiNativeTypeNum nativeTypeNum, dpiContext *context) {
    if (data->isNull) {
        return ATOM_NIL;
    }

    ERL_NIF_TERM value;
    switch (nativeTypeNum) {
        case DPI_NATIVE_TYPE_INT64:
            value = enif_make_int64(env, data->value.asInt64);
            break;
        case DPI_NATIVE_TYPE_UINT64:
            value = enif_make_uint64(env, data->value.asUint64);
            break;
        case DPI_NATIVE_TYPE_FLOAT: {
            char buf[64];
            int len = snprintf(buf, sizeof(buf), "%.17g", (double)data->value.asFloat);
            unsigned char *str = enif_make_new_binary(env, len, &value);
            memcpy(str, buf, len);
            break;
        }
        case DPI_NATIVE_TYPE_DOUBLE: {
            char buf[64];
            int len = snprintf(buf, sizeof(buf), "%.17g", data->value.asDouble);
            unsigned char *str = enif_make_new_binary(env, len, &value);
            memcpy(str, buf, len);
            break;
        }
        case DPI_NATIVE_TYPE_BYTES: {
            unsigned char *buf = enif_make_new_binary(env, data->value.asBytes.length, &value);
            memcpy(buf, data->value.asBytes.ptr, data->value.asBytes.length);
            break;
        }
        case DPI_NATIVE_TYPE_TIMESTAMP: {
            dpiTimestamp *ts = &data->value.asTimestamp;
            value = enif_make_tuple7(env,
                enif_make_int(env, ts->year),
                enif_make_uint(env, ts->month),
                enif_make_uint(env, ts->day),
                enif_make_uint(env, ts->hour),
                enif_make_uint(env, ts->minute),
                enif_make_uint(env, ts->second),
                enif_make_uint(env, ts->fsecond)
            );
            break;
        }
        case DPI_NATIVE_TYPE_INTERVAL_DS: {
            dpiIntervalDS *interval = &data->value.asIntervalDS;
            value = enif_make_tuple6(env,
                enif_make_atom(env, "interval_ds"),
                enif_make_int(env, interval->days),
                enif_make_int(env, interval->hours),
                enif_make_int(env, interval->minutes),
                enif_make_int(env, interval->seconds),
                enif_make_int(env, interval->fseconds)
            );
            break;
        }
        case DPI_NATIVE_TYPE_INTERVAL_YM: {
            dpiIntervalYM *interval = &data->value.asIntervalYM;
            value = enif_make_tuple3(env,
                enif_make_atom(env, "interval_ym"),
                enif_make_int(env, interval->years),
                enif_make_int(env, interval->months)
            );
            break;
        }
        case DPI_NATIVE_TYPE_ROWID: {
            dpiRowid *rowid = data->value.asRowid;
            const char *rowidStr;
            uint32_t rowidLen;
            if (dpiRowid_getStringValue(rowid, &rowidStr, &rowidLen) < 0) {
                return ATOM_NIL;
            }
            unsigned char *buf = enif_make_new_binary(env, rowidLen, &value);
            memcpy(buf, rowidStr, rowidLen);
            break;
        }
        default:
            value = ATOM_NIL;
            break;
    }

    return value;
}

// Get returned data from RETURNING INTO clause
// var_get_returned_data(var, pos) -> {:ok, [values]} | {:error, reason}
static ERL_NIF_TERM nif_var_get_returned_data(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 2) {
        return enif_make_badarg(env);
    }

    InexoraVariable *var_res;
    if (!enif_get_resource(env, argv[0], VARIABLE_RESOURCE_TYPE, (void **)&var_res)) {
        return make_error_tuple(env, "invalid_variable");
    }

    if (var_res->var == NULL) {
        return make_error_tuple(env, "variable_released");
    }

    unsigned int pos;
    if (!enif_get_uint(env, argv[1], &pos)) {
        return make_error_tuple(env, "invalid_position");
    }

    uint32_t numElements;
    dpiData *returnedData;
    if (dpiVar_getReturnedData(var_res->var, pos, &numElements, &returnedData) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(var_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    // Build list of returned values
    ERL_NIF_TERM *elements = enif_alloc(sizeof(ERL_NIF_TERM) * numElements);
    if (elements == NULL && numElements > 0) {
        return make_error_tuple(env, "allocation_failed");
    }

    for (uint32_t i = 0; i < numElements; i++) {
        elements[i] = data_to_term(env, &returnedData[i], var_res->nativeTypeNum, var_res->context);
    }

    ERL_NIF_TERM result_list = enif_make_list_from_array(env, elements, numElements);

    if (elements != NULL) {
        enif_free(elements);
    }

    return make_ok_tuple(env, result_list);
}

// Get value at array position (for reading back OUT variables)
// var_get_value(var, pos) -> {:ok, value} | {:error, reason}
static ERL_NIF_TERM nif_var_get_value(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 2) {
        return enif_make_badarg(env);
    }

    InexoraVariable *var_res;
    if (!enif_get_resource(env, argv[0], VARIABLE_RESOURCE_TYPE, (void **)&var_res)) {
        return make_error_tuple(env, "invalid_variable");
    }

    if (var_res->var == NULL) {
        return make_error_tuple(env, "variable_released");
    }

    unsigned int pos;
    if (!enif_get_uint(env, argv[1], &pos)) {
        return make_error_tuple(env, "invalid_position");
    }

    if (pos >= var_res->maxArraySize) {
        return make_error_tuple(env, "position_out_of_bounds");
    }

    ERL_NIF_TERM value = data_to_term(env, &var_res->data[pos], var_res->nativeTypeNum, var_res->context);

    return make_ok_tuple(env, value);
}

// Bind a variable by position
// stmt_bind_by_pos(stmt, pos, var) -> :ok | {:error, reason}
static ERL_NIF_TERM nif_stmt_bind_by_pos(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 3) {
        return enif_make_badarg(env);
    }

    InexoraStatement *stmt_res;
    if (!enif_get_resource(env, argv[0], STATEMENT_RESOURCE_TYPE, (void **)&stmt_res)) {
        return make_error_tuple(env, "invalid_statement");
    }

    if (stmt_res->stmt == NULL) {
        return make_error_tuple(env, "statement_closed");
    }

    unsigned int pos;
    if (!enif_get_uint(env, argv[1], &pos)) {
        return make_error_tuple(env, "invalid_position");
    }

    InexoraVariable *var_res;
    if (!enif_get_resource(env, argv[2], VARIABLE_RESOURCE_TYPE, (void **)&var_res)) {
        return make_error_tuple(env, "invalid_variable");
    }

    if (var_res->var == NULL) {
        return make_error_tuple(env, "variable_released");
    }

    if (dpiStmt_bindByPos(stmt_res->stmt, pos, var_res->var) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(stmt_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    return ATOM_OK;
}

// Bind a variable by name
// stmt_bind_by_name(stmt, name, var) -> :ok | {:error, reason}
static ERL_NIF_TERM nif_stmt_bind_by_name(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 3) {
        return enif_make_badarg(env);
    }

    InexoraStatement *stmt_res;
    if (!enif_get_resource(env, argv[0], STATEMENT_RESOURCE_TYPE, (void **)&stmt_res)) {
        return make_error_tuple(env, "invalid_statement");
    }

    if (stmt_res->stmt == NULL) {
        return make_error_tuple(env, "statement_closed");
    }

    ErlNifBinary name_bin;
    if (!enif_inspect_binary(env, argv[1], &name_bin)) {
        return make_error_tuple(env, "invalid_name");
    }

    InexoraVariable *var_res;
    if (!enif_get_resource(env, argv[2], VARIABLE_RESOURCE_TYPE, (void **)&var_res)) {
        return make_error_tuple(env, "invalid_variable");
    }

    if (var_res->var == NULL) {
        return make_error_tuple(env, "variable_released");
    }

    if (dpiStmt_bindByName(stmt_res->stmt, (const char *)name_bin.data, name_bin.size, var_res->var) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(stmt_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    return ATOM_OK;
}

// Execute statement multiple times (batch/array DML)
// stmt_execute_many(stmt, num_iters) -> {:ok, num_columns} | {:error, reason}
static ERL_NIF_TERM nif_stmt_execute_many(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 2) {
        return enif_make_badarg(env);
    }

    InexoraStatement *stmt_res;
    if (!enif_get_resource(env, argv[0], STATEMENT_RESOURCE_TYPE, (void **)&stmt_res)) {
        return make_error_tuple(env, "invalid_statement");
    }

    if (stmt_res->stmt == NULL) {
        return make_error_tuple(env, "statement_closed");
    }

    unsigned int num_iters;
    if (!enif_get_uint(env, argv[1], &num_iters) || num_iters == 0) {
        return make_error_tuple(env, "invalid_num_iters");
    }

    uint32_t numQueryColumns;
    if (dpiStmt_executeMany(stmt_res->stmt, DPI_MODE_EXEC_DEFAULT, num_iters) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(stmt_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    // Get number of query columns (will be 0 for DML)
    if (dpiStmt_getNumQueryColumns(stmt_res->stmt, &numQueryColumns) < 0) {
        // Not a query, return 0
        numQueryColumns = 0;
    }

    return make_ok_tuple(env, enif_make_uint(env, numQueryColumns));
}

// Release a variable
// var_release(var) -> :ok | {:error, reason}
static ERL_NIF_TERM nif_var_release(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 1) {
        return enif_make_badarg(env);
    }

    InexoraVariable *var_res;
    if (!enif_get_resource(env, argv[0], VARIABLE_RESOURCE_TYPE, (void **)&var_res)) {
        return make_error_tuple(env, "invalid_variable");
    }

    if (var_res->var != NULL) {
        dpiVar_release(var_res->var);
        var_res->var = NULL;
        var_res->data = NULL;
    }

    return ATOM_OK;
}

// ============================================================
// Cursor/Streaming Functions
// ============================================================

// Fetch multiple rows at once
// stmt_fetch_rows(stmt, max_rows) -> {:ok, {rows_fetched, more_rows}} | {:error, reason}
static ERL_NIF_TERM nif_stmt_fetch_rows(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 2) {
        return enif_make_badarg(env);
    }

    InexoraStatement *stmt_res;
    if (!enif_get_resource(env, argv[0], STATEMENT_RESOURCE_TYPE, (void **)&stmt_res)) {
        return make_error_tuple(env, "invalid_statement");
    }

    if (stmt_res->stmt == NULL) {
        return make_error_tuple(env, "statement_closed");
    }

    unsigned int max_rows;
    if (!enif_get_uint(env, argv[1], &max_rows) || max_rows == 0) {
        return make_error_tuple(env, "invalid_max_rows");
    }

    uint32_t bufferRowIndex;
    uint32_t numRowsFetched;
    int moreRows;

    if (dpiStmt_fetchRows(stmt_res->stmt, max_rows, &bufferRowIndex, &numRowsFetched, &moreRows) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(stmt_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    // Return {rows_fetched, buffer_row_index, more_rows}
    ERL_NIF_TERM result = enif_make_tuple3(env,
        enif_make_uint(env, numRowsFetched),
        enif_make_uint(env, bufferRowIndex),
        moreRows ? ATOM_TRUE : ATOM_FALSE);

    return make_ok_tuple(env, result);
}

// Set the internal array size used for fetching
// stmt_set_fetch_array_size(stmt, size) -> :ok | {:error, reason}
static ERL_NIF_TERM nif_stmt_set_fetch_array_size(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 2) {
        return enif_make_badarg(env);
    }

    InexoraStatement *stmt_res;
    if (!enif_get_resource(env, argv[0], STATEMENT_RESOURCE_TYPE, (void **)&stmt_res)) {
        return make_error_tuple(env, "invalid_statement");
    }

    if (stmt_res->stmt == NULL) {
        return make_error_tuple(env, "statement_closed");
    }

    unsigned int array_size;
    if (!enif_get_uint(env, argv[1], &array_size) || array_size == 0) {
        return make_error_tuple(env, "invalid_array_size");
    }

    if (dpiStmt_setFetchArraySize(stmt_res->stmt, array_size) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(stmt_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    return ATOM_OK;
}

// Get the internal array size used for fetching
// stmt_get_fetch_array_size(stmt) -> {:ok, size} | {:error, reason}
static ERL_NIF_TERM nif_stmt_get_fetch_array_size(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 1) {
        return enif_make_badarg(env);
    }

    InexoraStatement *stmt_res;
    if (!enif_get_resource(env, argv[0], STATEMENT_RESOURCE_TYPE, (void **)&stmt_res)) {
        return make_error_tuple(env, "invalid_statement");
    }

    if (stmt_res->stmt == NULL) {
        return make_error_tuple(env, "statement_closed");
    }

    uint32_t array_size;
    if (dpiStmt_getFetchArraySize(stmt_res->stmt, &array_size) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(stmt_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    return make_ok_tuple(env, enif_make_uint(env, array_size));
}

// Set the number of rows to prefetch
// stmt_set_prefetch_rows(stmt, num_rows) -> :ok | {:error, reason}
static ERL_NIF_TERM nif_stmt_set_prefetch_rows(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 2) {
        return enif_make_badarg(env);
    }

    InexoraStatement *stmt_res;
    if (!enif_get_resource(env, argv[0], STATEMENT_RESOURCE_TYPE, (void **)&stmt_res)) {
        return make_error_tuple(env, "invalid_statement");
    }

    if (stmt_res->stmt == NULL) {
        return make_error_tuple(env, "statement_closed");
    }

    unsigned int num_rows;
    if (!enif_get_uint(env, argv[1], &num_rows)) {
        return make_error_tuple(env, "invalid_num_rows");
    }

    if (dpiStmt_setPrefetchRows(stmt_res->stmt, num_rows) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(stmt_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    return ATOM_OK;
}

// Get the number of rows being prefetched
// stmt_get_prefetch_rows(stmt) -> {:ok, num_rows} | {:error, reason}
static ERL_NIF_TERM nif_stmt_get_prefetch_rows(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 1) {
        return enif_make_badarg(env);
    }

    InexoraStatement *stmt_res;
    if (!enif_get_resource(env, argv[0], STATEMENT_RESOURCE_TYPE, (void **)&stmt_res)) {
        return make_error_tuple(env, "invalid_statement");
    }

    if (stmt_res->stmt == NULL) {
        return make_error_tuple(env, "statement_closed");
    }

    uint32_t num_rows;
    if (dpiStmt_getPrefetchRows(stmt_res->stmt, &num_rows) < 0) {
        dpiErrorInfo errorInfo;
        dpiContext_getError(stmt_res->context, &errorInfo);
        return make_dpi_error(env, &errorInfo);
    }

    return make_ok_tuple(env, enif_make_uint(env, num_rows));
}


// ============================================================
// NIF Registration
// ============================================================

static ErlNifFunc nif_funcs[] = {
    // Context functions
    {"odpi_version", 0, nif_odpi_version, 0},
    {"context_create", 1, nif_context_create, 0},
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
    {"conn_get_transaction_in_progress", 1, nif_conn_get_transaction_in_progress, 0},
    // Statement functions
    {"stmt_prepare", 2, nif_stmt_prepare, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"stmt_execute", 1, nif_stmt_execute, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"stmt_fetch", 1, nif_stmt_fetch, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"stmt_get_query_info", 2, nif_stmt_get_query_info, 0},
    {"stmt_get_query_value", 2, nif_stmt_get_query_value, 0},
    {"stmt_get_row_count", 1, nif_stmt_get_row_count, 0},
    {"stmt_bind_value_by_pos", 4, nif_stmt_bind_value_by_pos, 0},
    {"stmt_bind_value_by_name", 4, nif_stmt_bind_value_by_name, 0},
    {"stmt_get_bind_names", 1, nif_stmt_get_bind_names, 0},
    {"stmt_close", 1, nif_stmt_close, 0},
    {"stmt_define_as_bytes", 3, nif_stmt_define_as_bytes, 0},
    // Variable functions (for batch/array operations)
    {"conn_new_var", 5, nif_conn_new_var, 0},
    {"var_set_num_elements", 2, nif_var_set_num_elements, 0},
    {"var_get_num_elements", 1, nif_var_get_num_elements, 0},
    {"var_set_from_bytes", 3, nif_var_set_from_bytes, 0},
    {"var_set_from_int", 3, nif_var_set_from_int, 0},
    {"var_set_from_double", 3, nif_var_set_from_double, 0},
    {"var_set_null", 2, nif_var_set_null, 0},
    {"var_get_returned_data", 2, nif_var_get_returned_data, 0},
    {"var_get_value", 2, nif_var_get_value, 0},
    {"var_release", 1, nif_var_release, 0},
    {"stmt_bind_by_pos", 3, nif_stmt_bind_by_pos, 0},
    {"stmt_bind_by_name", 3, nif_stmt_bind_by_name, 0},
    {"stmt_execute_many", 2, nif_stmt_execute_many, ERL_NIF_DIRTY_JOB_IO_BOUND},
    // Cursor/streaming functions
    {"stmt_fetch_rows", 2, nif_stmt_fetch_rows, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"stmt_set_fetch_array_size", 2, nif_stmt_set_fetch_array_size, 0},
    {"stmt_get_fetch_array_size", 1, nif_stmt_get_fetch_array_size, 0},
    {"stmt_set_prefetch_rows", 2, nif_stmt_set_prefetch_rows, 0},
    {"stmt_get_prefetch_rows", 1, nif_stmt_get_prefetch_rows, 0}
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
    ATOM_DONE = enif_make_atom(env, "done");

    // Context option atoms
    ATOM_DRIVER_NAME = enif_make_atom(env, "driver_name");
    ATOM_ORACLE_CLIENT_LIB_DIR = enif_make_atom(env, "oracle_client_lib_dir");
    ATOM_ORACLE_CLIENT_CONFIG_DIR = enif_make_atom(env, "oracle_client_config_dir");

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

    STATEMENT_RESOURCE_TYPE = enif_open_resource_type(
        env,
        NULL,
        "inexora_statement",
        statement_destructor,
        ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER,
        NULL
    );

    if (STATEMENT_RESOURCE_TYPE == NULL) {
        return -1;
    }

    VARIABLE_RESOURCE_TYPE = enif_open_resource_type(
        env,
        NULL,
        "inexora_variable",
        variable_destructor,
        ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER,
        NULL
    );

    if (VARIABLE_RESOURCE_TYPE == NULL) {
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
