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

// Connection resource struct - holds both context and connection
typedef struct {
    dpiContext *context;
    dpiConn *conn;
} InexoraConnection;

// Statement resource struct - holds context, connection, and statement
typedef struct {
    dpiContext *context;
    dpiConn *conn;
    dpiStmt *stmt;
} InexoraStatement;

// Atoms (initialized in on_load)
static ERL_NIF_TERM ATOM_OK;
static ERL_NIF_TERM ATOM_ERROR;
static ERL_NIF_TERM ATOM_NIL;
static ERL_NIF_TERM ATOM_TRUE;
static ERL_NIF_TERM ATOM_FALSE;
static ERL_NIF_TERM ATOM_DONE;

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

// Statement destructor (called when Erlang garbage collects the resource)
static void statement_destructor(ErlNifEnv *env, void *obj) {
    (void)env;
    InexoraStatement *stmt_res = (InexoraStatement *)obj;
    if (stmt_res->stmt != NULL) {
        dpiStmt_release(stmt_res->stmt);
        stmt_res->stmt = NULL;
    }
    // Note: We don't release conn/context here as they're managed separately
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

    // Handle nil/null
    if (enif_is_identical(argv[3], ATOM_NIL)) {
        data.isNull = 1;
        nativeType = DPI_NATIVE_TYPE_INT64; // Arbitrary type for NULL
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
    {"conn_get_transaction_in_progress", 1, nif_conn_get_transaction_in_progress, 0},
    // Statement functions
    {"stmt_prepare", 2, nif_stmt_prepare, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"stmt_execute", 1, nif_stmt_execute, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"stmt_fetch", 1, nif_stmt_fetch, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"stmt_get_query_info", 2, nif_stmt_get_query_info, 0},
    {"stmt_get_query_value", 2, nif_stmt_get_query_value, 0},
    {"stmt_get_row_count", 1, nif_stmt_get_row_count, 0},
    {"stmt_bind_value_by_pos", 4, nif_stmt_bind_value_by_pos, 0},
    {"stmt_close", 1, nif_stmt_close, 0},
    {"stmt_define_as_bytes", 3, nif_stmt_define_as_bytes, 0}
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
