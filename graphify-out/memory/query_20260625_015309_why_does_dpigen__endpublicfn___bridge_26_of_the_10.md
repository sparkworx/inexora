---
type: "query"
date: "2026-06-25T01:53:09.811501+00:00"
question: "Why does dpiGen__endPublicFn() bridge 26 of the 109 communities?"
contributor: "graphify"
source_nodes: ["dpiGen__endPublicFn()", "dpiGen__startPublicFn()", "dpiGen__release()", "dpiError", "dpiConn_prepareStmt()"]
---

# Q: Why does dpiGen__endPublicFn() bridge 26 of the 109 communities?

## Answer

dpiGen__endPublicFn() (dpiGen.c:246) is a STRUCTURAL choke point, not a semantic bridge. Per its source comment (L242-244) it 'should be the last call made in any public method using an ODPI-C handle'. Its sibling dpiGen__startPublicFn() (L313-319) is the first call: it validates the handle and acquires an error handle; endPublicFn releases that error handle back to the pool (L251-252) and returns. Because EVERY public dpi* function across every module (dpiConn_*, dpiStmt_*, dpiVar_*, dpiObject_*, dpiSodaDb_*) brackets its body with this start/end pair, the AST calls edges all converge here giving degree 219 spanning 26 communities. Caveat: nearly all incoming calls edges are INFERRED; only dpiGen__addRef/dpiGen__release are EXTRACTED, but the source confirms the convention (dpiGen__release L270/L272 literally calls it). dpiContext is the documented exception (handled differently), which is why dpiContext_createWithParams, the first call inexora NIF makes, does not route through it.

## Source Nodes

- dpiGen__endPublicFn()
- dpiGen__startPublicFn()
- dpiGen__release()
- dpiError
- dpiConn_prepareStmt()