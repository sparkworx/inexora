# Graph Report - .  (2026-07-17)

## Corpus Check
- 313 files · ~371,919 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2405 nodes · 11012 edges · 109 communities (69 shown, 40 thin omitted)
- Extraction: 49% EXTRACTED · 51% INFERRED · 0% AMBIGUOUS · INFERRED: 5611 edges (avg confidence: 0.8)
- Token cost: 0 input · 44,836 output

## Community Hubs (Navigation)
- Object Type & AQ Samples
- AQ Queues & Message Props
- Connection Pooling
- Inexora NIF Core
- Data Buffer Binds
- Ecto SQL Generation
- ODPI-C Connection Core
- LOB Handling
- Statement & Query Tests
- Statement Execution
- Handle & Variable Lifecycle
- Variable & Number Tests
- Data & JSON Buffers
- OCI AQ Bindings
- C Test Harness
- Vector Type
- Inexora.Nif Bindings
- Error & Debug Infrastructure
- SODA Collections
- SODA Collection Tests
- Connection Property Tests
- Temp LOB Demos
- Connection Creation & Params
- Inexora DBConnection Impl
- SODA Document Tests
- Inexora Project & Design Docs
- ODPI-C Sphinx Docs & Licensing
- NIF Design Sessions & Milestones
- CQN Subscriptions
- Inexora Elixir Tests
- AQ/Subscr Enumeration Docs
- JSON & Implicit Result Tests
- Connection & Context API Docs
- Environment & Globals
- Batch Error Tests
- OCI Library Loading
- JSON DOM
- SODA Database
- Object & Oracle Types
- SODA Document Cursor
- Inexora.Batch Operations
- SODA Collection Cursor
- ROWID Handling
- Connection Params & Auth Docs
- Two-Phase Commit Transactions
- Token Auth Demos
- Misc Data Tests
- Scrollable Cursor Tests
- Inexora.Type Conversion
- Vector Creation
- Sessionless Transactions
- DML Returning
- SODA Database Tests
- Ecto Oracle Adapter
- Inexora.Cursor Streaming
- Sphinx Doc Extensions
- Ecto Adapter SQL Tests
- Object Attributes
- Inexora.Query & Connect
- NIF Test Helpers
- Mix Project Config
- Data Type Info Docs
- AQ Message Enum Docs
- DB Startup/Shutdown Docs
- TPC Flags Docs
- Inexora.Result
- Ecto Integration Test
- Type Number Enum Docs
- Subscription Grouping Docs
- Bind JSON Demo
- CQN Demo
- Fetch JSON Demo
- Memory Leak Checker
- Inexora.Error
- Fetch Mode Docs
- JSON Options Docs
- Subscr OpCode/QOS Docs
- Pool Mode Docs
- Issue Templates
- PR Policy & Stale Bot
- Sharding Key Demo
- Sample Run Script
- Inexora Root Module
- Batch Binding Test
- NIF Unit Test
- Inexora Top Test
- Connection Close Mode Docs
- Session Purity Docs
- Server Type Docs
- SODA Flags Docs
- Statement Type Docs
- Rowid Functions Docs
- Var Returned Data Docs
- ConnInfo Docs
- ErrorInfo Docs
- Message Recipient Docs
- Debug Prefix Docs
- Single-File Embed Docs
- Announcements Template
- Doc Improvement Template
- Enhancement Request Template
- General Questions Template
- Installation Questions Template
- Oracle Copyright Notice

## God Nodes (most connected - your core abstractions)
1. `dpiTestCase_setFailedFromError()` - 424 edges
2. `dpiTestCase_getConnection()` - 337 edges
3. `dpiGen__endPublicFn()` - 219 edges
4. `dpiConn_prepareStmt()` - 211 edges
5. `dpiStmt_release()` - 204 edges
6. `dpiTestCase_expectError()` - 163 edges
7. `dpiConn_newVar()` - 144 edges
8. `dpiVar_release()` - 131 edges
9. `dpiTestCase_expectUintEqual()` - 114 edges
10. `dpiStmt_bindByPos()` - 105 edges

## Surprising Connections (you probably didn't know these)
- `Session: Implement Database Connection Plan + Cursor Streaming` --references--> `Minimal NIF Setup Milestone`  [INFERRED]
  2026-01-16-implement-the-following-plan.txt → 2026-01-15-what-are-we-trying-to-accomplish.txt
- `Oracle Instant Client Requirement` --conceptually_related_to--> `Oracle Instant Client Installation`  [INFERRED]
  README.md → c_src/odpi/doc/src/user_guide/installation.rst
- `dpiSamples__finalize()` --calls--> `dpiContext_destroy()`  [INFERRED]
  c_src/odpi/samples/SampleLib.c → c_src/odpi/src/dpiContext.c
- `ODPI-C Embed Single-File Compilation (embed/dpi.c)` --rationale_for--> `ODPI-C (Oracle Database Programming Interface for C)`  [INFERRED]
  2026-01-15-what-are-we-trying-to-accomplish.txt → c_src/odpi/README.md
- `Oracle Implicit Transaction (handle_begin marks state)` --conceptually_related_to--> `dpiStmt_execute`  [INFERRED]
  2026-01-16-implement-the-following-plan.txt → c_src/odpi/doc/src/functions/dpiStmt.rst

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Inexora Core Architectural Design Decisions** — 2026_01_16_context_per_connection_design, 2026_01_16_dirty_scheduler_io_bound, 2026_01_16_erlang_resource_destructor_cleanup, 2026_01_16_implicit_transaction_handle_begin [INFERRED 0.75]
- **Inexora Data Path: Types, Buffers, Round-Trips** — inexora_readme_data_type_mapping, c_src_odpi_doc_src_user_guide_data_types_odpi_type_support, c_src_odpi_doc_src_unions_dpidatabuffer_data_union, c_src_odpi_doc_src_user_guide_round_trips_fetch_array_size [INFERRED 0.75]
- **Advanced Queuing Dequeue Configuration** — c_src_odpi_doc_src_enums_dpideqmode_dpideqmode, c_src_odpi_doc_src_enums_dpideqnavigation_dpideqnavigation, c_src_odpi_doc_src_enums_dpieventtype_dpieventtype, concept_oracle_advanced_queuing [INFERRED 0.85]
- **ODPI-C Advanced Queueing Messaging Enumerations** — c_src_odpi_doc_src_enums_dpimessagedeliverymode_dpimessagedeliverymode, c_src_odpi_doc_src_enums_dpimessagestate_dpimessagestate, c_src_odpi_doc_src_enums_dpisodaflags_dpisodaflags [INFERRED 0.65]
- **ODPI-C Database Lifecycle Mode Enumerations** — c_src_odpi_doc_src_enums_dpistartupmode_dpistartupmode, c_src_odpi_doc_src_enums_dpishutdownmode_dpishutdownmode, c_src_odpi_doc_src_enums_dpipoolclosemode_dpipoolclosemode, c_src_odpi_doc_src_enums_dpipoolgetmode_dpipoolgetmode [INFERRED 0.75]
- **ODPI-C Subscription and Notification Enumerations** — c_src_odpi_doc_src_enums_dpiopcode_dpiopcode, c_src_odpi_doc_src_enums_dpisubscrgroupingclass_dpisubscrgroupingclass, c_src_odpi_doc_src_enums_dpisubscrgroupingtype_dpisubscrgroupingtype, c_src_odpi_doc_src_enums_dpisubscrnamespace_dpisubscrnamespace, c_src_odpi_doc_src_enums_dpisubscrprotocol_dpisubscrprotocol, c_src_odpi_doc_src_enums_dpisubscrqos_dpisubscrqos [INFERRED 0.85]
- **ODPI-C Object Type System** — c_src_odpi_doc_src_functions_dpiobjecttype_object_type_functions, c_src_odpi_doc_src_functions_dpiobject_object_functions, c_src_odpi_doc_src_functions_dpiobjectattr_object_attr_functions [EXTRACTED 1.00]
- **ODPI-C Advanced Queueing Messaging Components** — c_src_odpi_doc_src_functions_dpiqueue_queue_functions, c_src_odpi_doc_src_functions_dpimsgprops_msg_props_functions, c_src_odpi_doc_src_functions_dpideqoptions_deq_options_functions, c_src_odpi_doc_src_functions_dpienqoptions_enq_options_functions [EXTRACTED 1.00]
- **ODPI-C SODA Document Access Components** — c_src_odpi_doc_src_functions_dpisodadb_soda_db_functions, c_src_odpi_doc_src_functions_dpisodacoll_soda_coll_functions, c_src_odpi_doc_src_functions_dpisodacollcursor_soda_coll_cursor_functions, c_src_odpi_doc_src_functions_dpisodadoc_soda_doc_functions [EXTRACTED 1.00]
- **ODPI-C Statement/Variable Bind & Data Transfer Flow** — c_src_odpi_doc_src_functions_dpivar_dpiconn_newvar, c_src_odpi_doc_src_functions_dpistmt_dpistmt_bindbyname, c_src_odpi_doc_src_functions_dpistmt_dpistmt_bindbypos, c_src_odpi_doc_src_functions_dpistmt_dpistmt_define, c_src_odpi_doc_src_functions_dpivar_dpivar_getreturneddata [EXTRACTED 1.00]
- **ODPI-C Function Reference Documentation Set** — c_src_odpi_doc_src_functions_index_odpi_functions_reference, c_src_odpi_doc_src_functions_dpistmt_statement_functions, c_src_odpi_doc_src_functions_dpivar_variable_functions, c_src_odpi_doc_src_functions_dpivector_vector_functions, c_src_odpi_doc_src_functions_dpisubscr_subscription_functions, c_src_odpi_doc_src_functions_dpisodadoccursor_soda_doc_cursor_functions [EXTRACTED 1.00]
- **ODPI-C User Guide Documentation Set** — c_src_odpi_doc_src_index_odpi_documentation, c_src_odpi_doc_src_user_guide_introduction_odpi_overview, c_src_odpi_doc_src_user_guide_installation_oracle_instant_client, c_src_odpi_doc_src_user_guide_debugging_dpi_debug_level, c_src_odpi_doc_src_user_guide_data_types_odpi_type_support, c_src_odpi_doc_src_user_guide_round_trips_round_trip_table [EXTRACTED 1.00]
- **ODPI-C Connection/Pool Creation Parameter Structures** — c_src_odpi_doc_src_structs_dpicontextcreateparams_dpicontextcreateparams, c_src_odpi_doc_src_structs_dpicommoncreateparams_dpicommoncreateparams, c_src_odpi_doc_src_structs_dpiconncreateparams_dpiconncreateparams, c_src_odpi_doc_src_structs_dpipoolcreateparams_dpipoolcreateparams [INFERRED 0.85]
- **Structures embedding dpiDataTypeInfo** — c_src_odpi_doc_src_structs_dpidatatypeinfo_dpidatatypeinfo, c_src_odpi_doc_src_structs_dpiobjectattrinfo_dpiobjectattrinfo, c_src_odpi_doc_src_structs_dpiobjecttypeinfo_dpiobjecttypeinfo, c_src_odpi_doc_src_structs_dpiqueryinfo_dpiqueryinfo [EXTRACTED 1.00]
- **ODPI-C JSON Node Composition** — c_src_odpi_doc_src_structs_dpijsonnode_dpijsonnode, c_src_odpi_doc_src_structs_dpijsonarray_dpijsonarray, c_src_odpi_doc_src_structs_dpijsonobject_dpijsonobject, c_src_odpi_doc_src_structs_dpidata_dpidata [EXTRACTED 1.00]
- **Subscription Creation Flow** — c_src_odpi_doc_src_structs_dpisubscrcreateparams_dpisubscrcreateparams, c_src_odpi_doc_src_structs_dpisubscrcreateparams_dpisubscrcallback, c_src_odpi_doc_src_structs_dpisubscrmessage_dpisubscrmessage, c_src_odpi_doc_src_enums_dpieventtype_dpieventtype [INFERRED 0.85]
- **Subscription Notification Message Hierarchy** — c_src_odpi_doc_src_structs_dpisubscrmessage_dpisubscrmessage, c_src_odpi_doc_src_structs_dpisubscrmessagequery_dpisubscrmessagequery, c_src_odpi_doc_src_structs_dpisubscrmessagetable_dpisubscrmessagetable, c_src_odpi_doc_src_structs_dpisubscrmessagerow_dpisubscrmessagerow [EXTRACTED 1.00]
- **Oracle Client Library Loading and Versioning** — c_src_odpi_doc_src_user_guide_installation_client_lib_loading, c_src_odpi_doc_src_user_guide_installation_client_server_interop, c_src_odpi_doc_src_user_guide_installation_oracle_instant_client, c_src_odpi_doc_src_releasenotes_pre19_deprecation [INFERRED 0.75]
- **Adapter Split Across the DBConnection Seam** — docs_adapter_split_plan_adapter_split, docs_adr_0002_split_ecto_adapter_into_ecto_oracle_split_decision, docs_adapter_split_plan_frozen_public_interface, docs_adapter_split_plan_ecto_oracle_package, docs_adapter_split_plan_dbconnection_seam [EXTRACTED 1.00]
- **Type Owns Facts, Variable Stays Agnostic** — docs_adr_0001_type_owns_all_per_type_facts_type_ownership, docs_adr_0001_type_owns_all_per_type_facts_inexora_type, docs_adr_0001_type_owns_all_per_type_facts_inexora_variable, context_type_mapping, context_variable_spec [INFERRED 0.85]
- **dpiError Four-Layer Surface Path** — graphify_out_memory_query_20260625_020622_how_does_a_c_layer_dpierror_surface_into_the_elixi_error_surface_path, graphify_out_memory_query_20260625_020622_how_does_a_c_layer_dpierror_surface_into_the_elixi_lossy_error_contract, graphify_out_memory_query_20260625_020622_how_does_a_c_layer_dpierror_surface_into_the_elixi_context_use_after_free [EXTRACTED 1.00]

## Communities (109 total, 40 thin omitted)

### Community 0 - "Object Type & AQ Samples"
Cohesion: 0.06
Nodes (156): main(), main(), dpiConn_getObjectType(), dpiConn_newDeqOptions(), dpiConn_newEnqOptions(), dpiObject, dpiData_setDouble(), dpiData_setObject() (+148 more)

### Community 1 - "AQ Queues & Message Props"
Cohesion: 0.06
Nodes (129): main(), main(), dpiObjectType, dpiQueue, dpiConn_newMsgProps(), dpiConn_newQueue(), dpiConn, dpiDeqOptions (+121 more)

### Community 2 - "Connection Pooling"
Cohesion: 0.06
Nodes (106): dpiAccessToken, dpiConn, dpiConnCreateParams, dpiEncodingInfo, dpiError, dpiPool, UNUSED, dpiPool__accessTokenCallback() (+98 more)

### Community 3 - "Inexora NIF Core"
Cohesion: 0.08
Nodes (99): binary_to_cstring(), dpiContext, dpiData, dpiErrorInfo, dpiNativeTypeNum, connection_destructor(), context_destructor(), context_options_free() (+91 more)

### Community 4 - "Data Buffer Binds"
Cohesion: 0.10
Nodes (87): dpiBytes, dpiData, dpiTimestamp, dpiData_getBool(), dpiData_getBytes(), dpiData_getDouble(), dpiData_getFloat(), dpiData_getInt64() (+79 more)

### Community 5 - "Ecto SQL Generation"
Cohesion: 0.06
Nodes (72): Ecto.Adapters.Oracle.Connection, all(), boolean(), column_change(), column_definition(), column_definitions(), column_options(), column_type() (+64 more)

### Community 6 - "ODPI-C Connection Core"
Cohesion: 0.08
Nodes (82): dpiConn, dpiDataBuffer, dpiDeqOptions, dpiEncodingInfo, dpiEnqOptions, dpiJson, dpiMsgProps, dpiObject (+74 more)

### Community 7 - "LOB Handling"
Cohesion: 0.12
Nodes (65): dpiLob, dpiOracleTypeNum, dpiConn_newTempLob(), dpiConn, dpiError, dpiLob, dpiOracleType, dpiOracleTypeNum (+57 more)

### Community 8 - "Statement & Query Tests"
Cohesion: 0.14
Nodes (65): dpiStmt, dpiConn_prepareStmt(), dpiStmt_getInfo(), dpiConn, dpiTestCase, dpiTestParams, dpiTest_1600(), dpiTest_1601() (+57 more)

### Community 9 - "Statement Execution"
Cohesion: 0.12
Nodes (60): dpiOci__attrGet(), dpiConn, dpiData, dpiDataBuffer, dpiError, dpiErrorInfo, dpiNativeTypeNum, dpiObjectType (+52 more)

### Community 10 - "Handle & Variable Lifecycle"
Cohesion: 0.11
Nodes (56): dpiError__set(), dpiEnv, dpiError, dpiGen__addRef(), dpiGen__allocate(), dpiGen__checkHandle(), dpiGen__setRefCount(), dpiConn (+48 more)

### Community 11 - "Variable & Number Tests"
Cohesion: 0.17
Nodes (52): dpiData, dpiNativeTypeNum, dpiVar, dpiConn_newVar(), dpiJson_setFromText(), dpiVar_release(), dpiTestCase, dpiTestParams (+44 more)

### Community 12 - "Data & JSON Buffers"
Cohesion: 0.14
Nodes (47): dpiConn__setShardingKeyValue(), dpiDataBuffer, dpiEnv, dpiError, dpiJsonArray, dpiJsonObject, dpiLob, dpiStmt (+39 more)

### Community 13 - "OCI AQ Bindings"
Cohesion: 0.11
Nodes (45): dpiConn, dpiError, dpiJson, dpiJznDomDoc, dpiStmt, dpiVar, dpiOci__aqDeq(), dpiOci__aqDeqArray() (+37 more)

### Community 14 - "C Test Harness"
Cohesion: 0.11
Nodes (45): main(), main(), main(), main(), main(), main(), main(), main() (+37 more)

### Community 15 - "Vector Type"
Cohesion: 0.20
Nodes (44): dpiVector_release(), dpiConn, dpiNativeTypeNum, dpiOracleTypeNum, dpiTestCase, dpiTestParams, dpiVectorInfo, dpiTest_4400() (+36 more)

### Community 17 - "Error & Debug Infrastructure"
Cohesion: 0.09
Nodes (34): dpiDebug__getFormatWithPrefix(), dpiDebug__initialize(), dpiDebug__print(), dpiConn, dpiError, dpiErrorInfo, dpiError__getInfo(), dpiError__initHandle() (+26 more)

### Community 18 - "SODA Collections"
Cohesion: 0.19
Nodes (40): dpiOci__handleFree(), dpiError, dpiSodaColl, dpiSodaDb, dpiSodaDoc, dpiSodaDocCursor, dpiSodaOperOptions, dpiStringList (+32 more)

### Community 19 - "SODA Collection Tests"
Cohesion: 0.27
Nodes (37): dpiSodaDb_createCollection(), dpiSodaDb_release(), dpiSodaDoc_release(), dpiSodaColl, dpiSodaDb, dpiSodaDoc, dpiSodaOperOptions, dpiTestCase (+29 more)

### Community 20 - "Connection Property Tests"
Cohesion: 0.16
Nodes (36): dpiConn, dpiTestCase, dpiTestParams, dpiTest_1300(), dpiTest_1301(), dpiTest_1302(), dpiTest_1303(), dpiTest_1304() (+28 more)

### Community 21 - "Temp LOB Demos"
Cohesion: 0.19
Nodes (36): main(), main(), main(), main(), main(), main(), main(), main() (+28 more)

### Community 22 - "Connection Creation & Params"
Cohesion: 0.12
Nodes (36): dpiCommonCreateParams, dpiConnCreateParams, dpiContext, dpiError, dpiPool, dpiConn__attachExternal(), dpiConn__close(), dpiConn__create() (+28 more)

### Community 24 - "Inexora DBConnection Impl"
Cohesion: 0.10
Nodes (24): Inexora.Connection, bind_input_variables(), bind_output_variables(), bind_params(), cleanup_variables(), configure_cursor(), connection_dead?(), create_input_variables() (+16 more)

### Community 25 - "SODA Document Tests"
Cohesion: 0.20
Nodes (31): main(), main(), main(), main(), main(), main(), main(), main() (+23 more)

### Community 26 - "Inexora Project & Design Docs"
Cohesion: 0.07
Nodes (33): Two-Layer Error Handling Strategy, Inexora Project, Mirror ODPI-C Test Cases, Use Erlang NIFs over ODPI-C, NLS_LANG Test Pinning, Type Mapping, Value Binding, Variable (dpiVar lifecycle) (+25 more)

### Community 27 - "ODPI-C Sphinx Docs & Licensing"
Cohesion: 0.08
Nodes (31): Sphinx Documentation Build, Sphinx Build Requirements, ODPI-C Documentation Root, ODPI-C Dual License (UPL 1.0 / Apache 2.0), ODPI-C Release Notes, Pre-19 Client/Server Deprecation, dpiDataBuffer Union, dpiVectorDimensionBuffer Union (+23 more)

### Community 28 - "NIF Design Sessions & Milestones"
Cohesion: 0.07
Nodes (30): Minimal NIF Setup Milestone, ODPI-C Embed Single-File Compilation (embed/dpi.c), Session: What Are We Trying To Accomplish (Minimal NIF Setup), Context-Per-Connection Design Decision, Dirty Scheduler (ERL_NIF_DIRTY_JOB_IO_BOUND) for Network I/O, Erlang Resource Destructor Cleanup for dpiConn/dpiContext, Session: Implement Database Connection Plan + Cursor Streaming, Oracle Implicit Transaction (handle_begin marks state) (+22 more)

### Community 29 - "CQN Subscriptions"
Cohesion: 0.17
Nodes (28): dpiOci__collGetElem(), dpiOci__collSize(), dpiError, dpiStmt, dpiSubscr, dpiSubscrMessage, UNUSED, dpiSubscr_addRef() (+20 more)

### Community 30 - "Inexora Elixir Tests"
Cohesion: 0.11
Nodes (12): Inexora.ConnectionTest, Inexora.CursorTest, Inexora.ErrorTest, Inexora.FloatTypeTest, Inexora.IntervalTypeTest, Inexora.NamedParamsTest, Inexora.QueryExecutionTest, Inexora.QueryTest (+4 more)

### Community 31 - "AQ/Subscr Enumeration Docs"
Cohesion: 0.10
Nodes (28): dpiAuthMode, dpiCreateMode, dpiDeqMode, dpiDeqNavigation, dpiEventType, dpiExecMode, dpiSessionlessTransactionId, dpiShardingKeyColumn (+20 more)

### Community 32 - "JSON & Implicit Result Tests"
Cohesion: 0.27
Nodes (25): dpiJson, dpiData_getJson(), dpiJson_getValue(), dpiTestCase, dpiTestParams, dpiTest_2900(), dpiTest_2901(), dpiConn (+17 more)

### Community 33 - "Connection & Context API Docs"
Cohesion: 0.12
Nodes (25): dpiVectorFlags Enumeration, dpiVectorFormat Enumeration, dpiVisibility Enumeration, ODPI-C Enumerations Index, Advanced Queueing (AQ) Messaging, ODPI-C Connection Functions (dpiConn), Handle Reference-Counting Lifecycle Pattern, ODPI-C Context Functions (dpiContext) (+17 more)

### Community 34 - "Environment & Globals"
Cohesion: 0.14
Nodes (23): dpiCommonCreateParams, dpiContext, dpiEncodingInfo, dpiEnv, dpiError, dpiEnv__free(), dpiEnv__getBaseDate(), dpiEnv__getCharacterSetIdAndName() (+15 more)

### Community 35 - "Batch Error Tests"
Cohesion: 0.17
Nodes (23): dpiConn, dpiStmt, dpiTestCase, dpiTestParams, dpiTest_3200(), dpiTest_3201(), dpiTest_3202(), dpiTest__prepareInsertWithErrors() (+15 more)

### Community 36 - "OCI Library Loading"
Cohesion: 0.19
Nodes (22): dpiContextCreateParams, dpiVersionInfo, dpiOci__calculateConfigDir(), dpiOci__checkDllArchitecture(), dpiOci__findAndCheckDllArchitecture(), dpiOci__getEnv(), dpiOci__getModuleDir(), dpiOci__loadLib() (+14 more)

### Community 37 - "JSON DOM"
Cohesion: 0.27
Nodes (20): dpiConn, dpiError, dpiJson, dpiJsonArray, dpiJsonNode, dpiJsonObject, dpiJznDomDoc, dpiJson_addRef() (+12 more)

### Community 38 - "SODA Database"
Cohesion: 0.21
Nodes (18): main(), dpiError, dpiJsonNode, dpiSodaCollCursor, dpiSodaDb, dpiSodaDoc, dpiStringList, UNUSED (+10 more)

### Community 39 - "Object & Oracle Types"
Cohesion: 0.21
Nodes (18): dpiConn, dpiError, dpiObjectType, dpiObjectType_addRef(), dpiObjectType__allocate(), dpiObjectType__check(), dpiObjectType__describe(), dpiObjectType__free() (+10 more)

### Community 40 - "SODA Document Cursor"
Cohesion: 0.19
Nodes (18): dpiError, dpiSodaColl, dpiSodaDoc, dpiSodaDocCursor, UNUSED, dpiSodaDocCursor_addRef(), dpiSodaDocCursor__allocate(), dpiSodaDocCursor__check() (+10 more)

### Community 41 - "Inexora.Batch Operations"
Cohesion: 0.18
Nodes (16): Inexora.Batch, bind_input_variables(), bind_output_variables(), create_column_variable(), create_input_variables(), create_output_variables(), encode_value(), execute_batch() (+8 more)

### Community 42 - "SODA Collection Cursor"
Cohesion: 0.20
Nodes (17): main(), dpiError, dpiSodaColl, dpiSodaCollCursor, dpiSodaDb, UNUSED, dpiSodaCollCursor_addRef(), dpiSodaCollCursor__allocate() (+9 more)

### Community 43 - "ROWID Handling"
Cohesion: 0.34
Nodes (18): dpiRowid_getStringValue(), dpiStmt_bindValueByPos(), dpiTestCase, dpiTestParams, dpiTest_4200(), dpiTest_4201(), dpiTest_4202(), dpiTest_4203() (+10 more)

### Community 44 - "Connection Params & Auth Docs"
Cohesion: 0.14
Nodes (18): dpiAccessToken, Token Based Authentication, dpiAppContext, dpiBytes, dpiCommonCreateParams, Database Sharding, dpiConnCreateParams, DRCP (Database Resident Connection Pooling) (+10 more)

### Community 45 - "Two-Phase Commit Transactions"
Cohesion: 0.36
Nodes (17): dpiConn_tpcBegin(), dpiConn, dpiTestCase, dpiTestParams, dpiXid, dpiTest_1700(), dpiTest_1701(), dpiTest_1702() (+9 more)

### Community 46 - "Token Auth Demos"
Cohesion: 0.22
Nodes (14): dpiAccessToken, main(), tokenCallback(), main(), dpiAccessToken, dpiSamples__fatalError(), dpiSamples__finalize(), dpiSamples_getAccessToken() (+6 more)

### Community 47 - "Misc Data Tests"
Cohesion: 0.30
Nodes (14): dpiData_getIsNull(), dpiConn, dpiStmt, dpiTestCase, dpiTestParams, dpiTest_1800(), dpiTest_1801(), dpiTest_1802() (+6 more)

### Community 48 - "Scrollable Cursor Tests"
Cohesion: 0.33
Nodes (14): dpiConn, dpiStmt, dpiTestCase, dpiTestParams, dpiTest_3000(), dpiTest_3001(), dpiTest_3002(), dpiTest_3003() (+6 more)

### Community 49 - "Inexora.Type Conversion"
Cohesion: 0.14
Nodes (4): Inexora.Type, convert_from_oracle(), to_elixir(), Inexora.TypeTest

### Community 50 - "Vector Creation"
Cohesion: 0.26
Nodes (13): dpiVector, dpiVectorInfo, dpiConn__newVector(), dpiConn, dpiError, dpiVector, dpiVectorInfo, dpiVector_addRef() (+5 more)

### Community 51 - "Sessionless Transactions"
Cohesion: 0.42
Nodes (12): dpiConn_beginSessionlessTransaction(), dpiConn_resumeSessionlessTransaction(), dpiConn__startSessionlessTransaction(), dpiTestCase, dpiTestParams, dpiTest_4500(), dpiTest_4501(), dpiTest_4502() (+4 more)

### Community 52 - "DML Returning"
Cohesion: 0.49
Nodes (12): dpiVar_getReturnedData(), dpiConn, dpiTestCase, dpiTestParams, dpiTest_3300(), dpiTest_3301(), dpiTest_3302(), dpiTest_3303() (+4 more)

### Community 53 - "SODA Database Tests"
Cohesion: 0.38
Nodes (11): dpiSodaDb, dpiTestCase, dpiTestParams, dpiTest_3400(), dpiTest_3401(), dpiTest_3402(), dpiTest_3403(), dpiTest_3404() (+3 more)

### Community 55 - "Inexora.Cursor Streaming"
Cohesion: 0.27
Nodes (11): Inexora.Cursor, bind_params(), configure_fetch(), fetch(), fetch_batch(), fetch_next(), fetch_row_values(), get_columns() (+3 more)

### Community 56 - "Sphinx Doc Extensions"
Cohesion: 0.24
Nodes (5): ParametersTable, setup(), HTMLTranslator, ListTableWithSummary, setup()

### Community 57 - "Ecto Adapter SQL Tests"
Cohesion: 0.18
Nodes (3): Ecto.Adapters.OracleTest, Schema, Schema2

### Community 58 - "Object Attributes"
Cohesion: 0.36
Nodes (8): dpiError, dpiObjectAttr, dpiObjectAttrInfo, dpiObjectType, dpiObjectAttr_addRef(), dpiObjectAttr__allocate(), dpiObjectAttr__free(), dpiObjectAttr_getInfo()

### Community 59 - "Inexora.Query & Connect"
Cohesion: 0.25
Nodes (5): build_connect_string(), connect(), set_variable_value(), Inexora.Query, to_string()

### Community 60 - "NIF Test Helpers"
Cohesion: 0.28
Nodes (6): Inexora.NifConnectionTest, create_test_connection(), Inexora.TestHelpers, connect_test_db(), connect_test_db_nif(), test_connection_opts()

### Community 61 - "Mix Project Config"
Cohesion: 0.43
Nodes (5): Inexora.MixProject, deps(), docs(), package(), project()

### Community 62 - "Data Type Info Docs"
Cohesion: 0.50
Nodes (5): dpiAnnotation, dpiDataTypeInfo, dpiObjectAttrInfo, dpiObjectTypeInfo, dpiQueryInfo

### Community 63 - "AQ Message Enum Docs"
Cohesion: 0.50
Nodes (4): dpiMessageDeliveryMode Enumeration, dpiMessageState Enumeration, dpiSubscrNamespace Enumeration, dpiSubscrProtocol Enumeration

### Community 67 - "Ecto Integration Test"
Cohesion: 0.50
Nodes (3): Ecto.Adapters.OracleIntegrationTest, TestRepo, User

### Community 68 - "Type Number Enum Docs"
Cohesion: 0.67
Nodes (3): dpiDataBuffer Structure, dpiNativeTypeNum Enumeration, dpiOracleTypeNum Enumeration

### Community 69 - "Subscription Grouping Docs"
Cohesion: 1.00
Nodes (3): dpiSubscrCreateParams Structure, dpiSubscrGroupingClass Enumeration, dpiSubscrGroupingType Enumeration

## Knowledge Gaps
- **98 isolated node(s):** `run.sh script`, `Inexora`, `Ecto.Adapters.OracleIntegrationTest`, `TestRepo`, `User` (+93 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **40 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `dpiGen__endPublicFn()` connect `ODPI-C Connection Core` to `Object Type & AQ Samples`, `AQ Queues & Message Props`, `Connection Pooling`, `Inexora NIF Core`, `Data Buffer Binds`, `LOB Handling`, `Statement & Query Tests`, `Statement Execution`, `Handle & Variable Lifecycle`, `Variable & Number Tests`, `Error & Debug Infrastructure`, `SODA Collections`, `SODA Collection Tests`, `Temp LOB Demos`, `Connection Creation & Params`, `SODA Document Tests`, `CQN Subscriptions`, `JSON & Implicit Result Tests`, `JSON DOM`, `SODA Database`, `SODA Document Cursor`, `SODA Collection Cursor`, `ROWID Handling`, `Two-Phase Commit Transactions`, `Vector Creation`, `Sessionless Transactions`, `DML Returning`, `Object Attributes`?**
  _High betweenness centrality (0.146) - this node is a cross-community bridge._
- **Why does `dpiTestCase_setFailedFromError()` connect `Statement & Query Tests` to `Object Type & AQ Samples`, `AQ Queues & Message Props`, `Connection Pooling`, `Inexora NIF Core`, `Data Buffer Binds`, `LOB Handling`, `Variable & Number Tests`, `Vector Type`, `SODA Collection Tests`, `Connection Property Tests`, `Temp LOB Demos`, `SODA Document Tests`, `CQN Subscriptions`, `JSON & Implicit Result Tests`, `Batch Error Tests`, `SODA Document Cursor`, `SODA Collection Cursor`, `ROWID Handling`, `Two-Phase Commit Transactions`, `Misc Data Tests`, `Scrollable Cursor Tests`, `Sessionless Transactions`, `DML Returning`, `SODA Database Tests`?**
  _High betweenness centrality (0.098) - this node is a cross-community bridge._
- **Why does `dpiConn_prepareStmt()` connect `Statement & Query Tests` to `Object Type & AQ Samples`, `Connection Pooling`, `Inexora NIF Core`, `Data Buffer Binds`, `ODPI-C Connection Core`, `LOB Handling`, `Statement Execution`, `Variable & Number Tests`, `Vector Type`, `Connection Property Tests`, `Temp LOB Demos`, `JSON & Implicit Result Tests`, `Batch Error Tests`, `ROWID Handling`, `Two-Phase Commit Transactions`, `Misc Data Tests`, `Scrollable Cursor Tests`, `Sessionless Transactions`, `DML Returning`, `Sharding Key Demo`?**
  _High betweenness centrality (0.042) - this node is a cross-community bridge._
- **Are the 413 inferred relationships involving `dpiTestCase_setFailedFromError()` (e.g. with `dpiTest_1100()` and `dpiTest_1101()`) actually correct?**
  _`dpiTestCase_setFailedFromError()` has 413 INFERRED edges - model-reasoned connections that need verification._
- **Are the 332 inferred relationships involving `dpiTestCase_getConnection()` (e.g. with `dpiTest_1100()` and `dpiTest_1101()`) actually correct?**
  _`dpiTestCase_getConnection()` has 332 INFERRED edges - model-reasoned connections that need verification._
- **Are the 215 inferred relationships involving `dpiGen__endPublicFn()` (e.g. with `dpiConn_beginSessionlessTransaction()` and `dpiConn_breakExecution()`) actually correct?**
  _`dpiGen__endPublicFn()` has 215 INFERRED edges - model-reasoned connections that need verification._
- **Are the 207 inferred relationships involving `dpiConn_prepareStmt()` (e.g. with `nif_stmt_prepare()` and `main()`) actually correct?**
  _`dpiConn_prepareStmt()` has 207 INFERRED edges - model-reasoned connections that need verification._