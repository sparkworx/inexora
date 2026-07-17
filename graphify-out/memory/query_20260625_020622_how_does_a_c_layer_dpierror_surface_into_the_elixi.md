---
type: "query"
date: "2026-06-25T02:06:22.173966+00:00"
question: "How does a C-layer dpiError surface into the Elixir Inexora.Error struct, and where do OTP resources get dropped?"
contributor: "graphify"
source_nodes: ["make_dpi_error()", "make_error_tuple()", "Inexora.Connection", "Inexora.Type", "dpiErrorInfo", "inexora_nif.c"]
---

# Q: How does a C-layer dpiError surface into the Elixir Inexora.Error struct, and where do OTP resources get dropped?

## Answer

ERROR PATH (4 layers): (1) ODPI-C call fails -> dpiContext_getError(ctx,&errorInfo) fills dpiErrorInfo (inexora_nif.c:404,461,546,571). (2) make_dpi_error (inexora_nif.c:91-98) marshals a fixed {:error,{code,fnName,message}} 3-tuple; platform errors take make_error_tuple (:86-88) -> {:error,binary}. (3) GRAPH GAP: graphify path found NO edge make_dpi_error->Inexora.Error because cross-language calls edges are forbidden; the NIF returns a term, it does not call Elixir. The only binding is an IMPLICIT contract: C 3-tuple at :92-97 must match Elixir destructure at error.ex:41. (4) Inexora.Connection (connection.ex:67,90,162,194...) funnels {:error,reason} through Error.from_odpi/1 (error.ex:41-60) -> %Inexora.Error{}; Ecto adapter to_constraints (connection.ex:1276) maps codes. CONTRACT IS LOSSY: dpiErrorInfo (dpi.h) has 11 fields; make_dpi_error forwards 3. action is plumbed in the struct (error.ex:9) but always nil; isRecoverable/sqlState/isWarning/offset dropped entirely. DROPPED BALL (resources): context_destructor (inexora_nif.c:203) calls dpiContext_destroy, but nif_conn_create (:480) stores context as a RAW pointer with no enif_keep_resource. Statements/Variables pin their parent conn (enif_keep_resource :728,:1810; released in dtors :259,:288) but nothing pins the context. Graceful disconnect/2 (connection.ex:74-75) closes conn then destroys context in order, masking it; on abnormal process death (no disconnect) the BEAM GC can run context_destructor before connection_destructor -> dpiConn_release on a conn whose ODPI-C env is freed -> use-after-free. FIX: conn must enif_keep_resource the context to complete the stmt->conn->context pin chain.

## Source Nodes

- make_dpi_error()
- make_error_tuple()
- Inexora.Connection
- Inexora.Type
- dpiErrorInfo
- inexora_nif.c