// c_src/inexora_nif.c
// Inexora NIF - Oracle Database driver for Elixir via ODPI-C

#include <erl_nif.h>
#include <string.h>
#include "dpi.h"

// Resource type for dpiContext
static ErlNifResourceType *CONTEXT_RESOURCE_TYPE;

// Atoms (initialized in on_load)
static ERL_NIF_TERM ATOM_OK;
static ERL_NIF_TERM ATOM_ERROR;
static ERL_NIF_TERM ATOM_NIL;

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
// NIF Registration
// ============================================================

static ErlNifFunc nif_funcs[] = {
    {"odpi_version", 0, nif_odpi_version, 0},
    {"context_create", 0, nif_context_create, 0},
    {"context_destroy", 1, nif_context_destroy, 0},
    {"get_client_version", 1, nif_get_client_version, 0}
};

// on_load callback - initialize resources and atoms
static int on_load(ErlNifEnv *env, void **priv_data, ERL_NIF_TERM load_info) {
    (void)priv_data;
    (void)load_info;

    // Create atoms
    ATOM_OK = enif_make_atom(env, "ok");
    ATOM_ERROR = enif_make_atom(env, "error");
    ATOM_NIL = enif_make_atom(env, "nil");

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
