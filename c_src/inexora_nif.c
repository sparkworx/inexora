#include "dpi.h"
#include <erl_nif.h>

static ERL_NIF_TERM hello_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
#pragma unused(argc)
#pragma unused(argv)
    return enif_make_string(env, "world", ERL_NIF_UTF8);
}

static ERL_NIF_TERM create_context_nif(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
#pragma unused(argc)
#pragma unused(argv)
    dpiContext *ctx;
    dpiErrorInfo err;

    // check argv[] instead of ignoring, parse options list

    int rc = dpiContext_createWithParams(DPI_MAJOR_VERSION, DPI_MINOR_VERSION, NULL, &ctx, &err);

    if (rc < 0) {
        return enif_make_tuple2(env, enif_make_atom(env, "error"), enif_make_string(env, err.message, ERL_NIF_UTF8));
    } else {
        return enif_make_tuple2(env, enif_make_atom(env, "ok"), enif_make_resource(env, ctx));
    }
}

static ErlNifFunc nif_funcs[] = {
    { "hello", 0, hello_nif, 0 },
    { "create_context", 1, create_context_nif, ERL_NIF_DIRTY_JOB_IO_BOUND }
};

ERL_NIF_INIT(Elixir.InexoraNIF, nif_funcs, NULL, NULL, NULL, NULL)
