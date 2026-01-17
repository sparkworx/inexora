#ifndef INEXORA_MEM_H
#define INEXORA_MEM_H

/*
 * Memory allocation shim for Inexora
 *
 * This header redirects malloc/calloc/realloc/free to Erlang NIF allocators.
 * It must be included FIRST via compiler -include flag before any other headers.
 *
 * Benefits:
 * - Memory is tracked by Erlang's memory instrumentation
 * - Better integration with Erlang's scheduler and garbage collector
 * - Memory usage visible via :erlang.memory(:nif_alloc)
 */

#include <stddef.h>    /* size_t */
#include <string.h>    /* memset */
#include <erl_nif.h>   /* enif_alloc, enif_free, enif_realloc */

/* Wrapper functions using Erlang NIF allocators */

static inline void* inexora_malloc(size_t size) {
    return enif_alloc(size);
}

static inline void* inexora_calloc(size_t count, size_t size) {
    size_t total = count * size;
    void* ptr = enif_alloc(total);
    if (ptr) {
        memset(ptr, 0, total);
    }
    return ptr;
}

static inline void* inexora_realloc(void* ptr, size_t size) {
    return enif_realloc(ptr, size);
}

static inline void inexora_free(void* ptr) {
    if (ptr) {
        enif_free(ptr);
    }
}

/* Redirect standard allocators to our wrappers */
#define malloc(size)         inexora_malloc(size)
#define calloc(count, size)  inexora_calloc(count, size)
#define realloc(ptr, size)   inexora_realloc(ptr, size)
#define free(ptr)            inexora_free(ptr)

#endif /* INEXORA_MEM_H */
