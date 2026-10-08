# ash_r2rml reference

<!-- ============================================================= -->
<!-- AGENT-FORBIDDEN-BEGIN: reference body is RIGID                -->
<!-- Every row below is rendered from queries/ast_extract.rq.      -->
<!-- Agents MUST NOT add, edit, reorder, or remove any row or      -->
<!-- table cell. Prose outside the fenced slot below is refused    -->
<!-- by the doc_quality court.                                     -->
<!-- ============================================================= -->

## Modules


### Admission

| `admit` | function | admit/2 |  |  |  |  |

| `cap` | function | cap/6 |  |  |  |  |

| `catalog` | function | catalog/0 |  |  |  |  |

| `classify` | function | classify/2 |  |  |  |  |

| `closure` | function | closure/1 |  |  |  |  |

| `evidence_plan` | function | evidence_plan/2 |  |  |  |  |

| `expand` | function | expand/3 |  |  |  |  |

| `expand` | function | expand/3 |  |  |  |  |

| `fetch` | function | fetch/3 |  |  |  |  |

| `graph_sha256` | function | graph_sha256/0 |  |  |  |  |

| `normalize_observation` | function | normalize_observation/1 |  |  |  |  |

| `normalize_observation` | function | normalize_observation/1 |  |  |  |  |

| `valid_observation?` | function | valid_observation?/2 |  |  |  |  |


### Admission


### AshPostgresFixture.Domain


### AshPostgresFixture.MerchantAccount


### AshPostgresFixture.Repo


### AshR2RML

| `admit_knowledge_hooks` | function | admit_knowledge_hooks/2 |  |  |  |  |

| `compile_api_bundle` | function | compile_api_bundle/2 |  |  |  |  |

| `compile_bundle` | function | compile_bundle/2 |  |  |  |  |

| `compile_jsonld` | function | compile_jsonld/2 |  |  |  |  |

| `compile_jsonld_bundle` | function | compile_jsonld_bundle/2 |  |  |  |  |

| `compile_knowledge_hook_specs` | function | compile_knowledge_hook_specs/1 |  |  |  |  |

| `compile_knowledge_hooks_bundle` | function | compile_knowledge_hooks_bundle/2 |  |  |  |  |

| `compile_knowledge_hooks_turtle_bundle` | function | compile_knowledge_hooks_turtle_bundle/2 |  |  |  |  |

| `compile_production` | function | compile_production/2 |  |  |  |  |

| `compile_turtle` | function | compile_turtle/2 |  |  |  |  |

| `compile_turtle_bundle` | function | compile_turtle_bundle/2 |  |  |  |  |

| `evaluate_knowledge_hook_promotion` | function | evaluate_knowledge_hook_promotion/3 |  |  |  |  |

| `evaluate_knowledge_hooks` | function | evaluate_knowledge_hooks/2 |  |  |  |  |

| `ingest_jsonld` | function | ingest_jsonld/2 |  |  |  |  |

| `ingest_knowledge_hooks_turtle` | function | ingest_knowledge_hooks_turtle/2 |  |  |  |  |

| `ingest_turtle` | function | ingest_turtle/2 |  |  |  |  |

| `plan_sparql` | function | plan_sparql/2 |  |  |  |  |

| `production_admit` | function | production_admit/3 |  |  |  |  |

| `production_candidates` | function | production_candidates/1 |  |  |  |  |

| `project_knowledge_hook_target` | function | project_knowledge_hook_target/1 |  |  |  |  |

| `schedule_knowledge_hook_specs` | function | schedule_knowledge_hook_specs/1 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |


### AshR2RML.Admission

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `datatype_projection` | function | datatype_projection/1 |  |  |  |  |

| `normalize_attributes` | function | normalize_attributes/1 |  |  |  |  |

| `normalize_attributes` | function | normalize_attributes/1 |  |  |  |  |

| `normalize_identities` | function | normalize_identities/1 |  |  |  |  |

| `normalize_resource` | function | normalize_resource/1 |  |  |  |  |

| `normalize_resource` | function | normalize_resource/1 |  |  |  |  |

| `normalize_resources` | function | normalize_resources/1 |  |  |  |  |

| `normalize_resources` | function | normalize_resources/1 |  |  |  |  |


### AshR2RML.AttributeMapping


### AshR2RML.Bounds

| `admit_input` | function | admit_input/2 |  |  |  |  |

| `admit_profile` | function | admit_profile/1 |  |  |  |  |

| `admit_profile` | function | admit_profile/1 |  |  |  |  |

| `defaults` | function | defaults/0 |  |  |  |  |

| `get` | function | get/3 |  |  |  |  |

| `get_option` | function | get_option/3 |  |  |  |  |

| `get_option` | function | get_option/3 |  |  |  |  |

| `get_option` | function | get_option/3 |  |  |  |  |

| `input_bytes` | function | input_bytes/1 |  |  |  |  |

| `input_bytes` | function | input_bytes/1 |  |  |  |  |

| `integer_or_zero` | function | integer_or_zero/1 |  |  |  |  |

| `integer_or_zero` | function | integer_or_zero/1 |  |  |  |  |

| `max_nested` | function | max_nested/2 |  |  |  |  |

| `normalized_limits` | function | normalized_limits/1 |  |  |  |  |

| `normalized_limits` | function | normalized_limits/1 |  |  |  |  |

| `total_members` | function | total_members/1 |  |  |  |  |


### AshR2RML.CheatSheet

| `generate` | function | generate/0 |  |  |  |  |


### AshR2RML.Compilation


### AshR2RML.CompilationReceipt


### AshR2RML.Compiler

| `attach_parity_witness` | function | attach_parity_witness/3 |  |  |  |  |

| `attach_parity_witness` | function | attach_parity_witness/3 |  |  |  |  |

| `attribute_column` | function | attribute_column/2 |  |  |  |  |

| `authorize_cutover` | function | authorize_cutover/2 |  |  |  |  |

| `canonical_ir` | function | canonical_ir/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile_resources` | function | compile_resources/1 |  |  |  |  |

| `convert_references` | function | convert_references/2 |  |  |  |  |

| `cutover_ready?` | function | cutover_ready?/0 |  |  |  |  |

| `cutover_ready?` | function | cutover_ready?/1 |  |  |  |  |

| `do_closure` | function | do_closure/3 |  |  |  |  |

| `do_closure` | function | do_closure/3 |  |  |  |  |

| `explore` | function | explore/1 |  |  |  |  |

| `projection_refusals` | function | projection_refusals/1 |  |  |  |  |

| `public_refusal_compilation` | function | public_refusal_compilation/2 |  |  |  |  |

| `receipt` | function | receipt/8 |  |  |  |  |

| `refusal_compilation` | function | refusal_compilation/2 |  |  |  |  |

| `refusal_receipt` | function | refusal_receipt/2 |  |  |  |  |

| `render_all` | function | render_all/2 |  |  |  |  |

| `render_storage_ddl` | function | render_storage_ddl/2 |  |  |  |  |

| `render_storage_ddl` | function | render_storage_ddl/2 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `storage_map` | function | storage_map/2 |  |  |  |  |

| `storage_render_step` | function | storage_render_step/1 |  |  |  |  |

| `storage_render_step` | function | storage_render_step/1 |  |  |  |  |


### AshR2RML.DataLayer

| `backend` | function | backend/1 |  |  |  |  |

| `default_table_name` | function | default_table_name/1 |  |  |  |  |

| `ets_table_name` | function | ets_table_name/1 |  |  |  |  |

| `generic_table_name` | function | generic_table_name/1 |  |  |  |  |

| `infer_join_columns` | function | infer_join_columns/2 |  |  |  |  |

| `postgres_table_name` | function | postgres_table_name/1 |  |  |  |  |

| `schema_name` | function | schema_name/1 |  |  |  |  |

| `table_name` | function | table_name/1 |  |  |  |  |


### AshR2RML.Datatype.Registry

| `absolute_iri?` | function | absolute_iri?/1 |  |  |  |  |

| `builtin_contracts` | function | builtin_contracts/0 |  |  |  |  |

| `builtin_storage` | function | builtin_storage/1 |  |  |  |  |

| `enum_type?` | function | enum_type?/1 |  |  |  |  |

| `legacy_literal_type?` | function | legacy_literal_type?/1 |  |  |  |  |

| `normalize_ash_type` | function | normalize_ash_type/1 |  |  |  |  |

| `normalize_ash_type` | function | normalize_ash_type/1 |  |  |  |  |

| `resolve` | function | resolve/3 |  |  |  |  |

| `semantic_contract` | function | semantic_contract/1 |  |  |  |  |

| `semantic_contract` | function | semantic_contract/1 |  |  |  |  |

| `semantic_literal?` | function | semantic_literal?/1 |  |  |  |  |

| `semantic_literal?` | function | semantic_literal?/1 |  |  |  |  |

| `semantic_storage` | function | semantic_storage/1 |  |  |  |  |

| `supported?` | function | supported?/1 |  |  |  |  |


### AshR2RML.Delta

| `default_iterations` | function | default_iterations/0 |  |  |  |  |

| `diff` | function | diff/2 |  |  |  |  |

| `root_digest` | function | root_digest/1 |  |  |  |  |

| `spec_budget_ms` | function | spec_budget_ms/0 |  |  |  |  |

| `triple_set` | function | triple_set/1 |  |  |  |  |


### AshR2RML.DfCM

| `admit` | function | admit/2 |  |  |  |  |

| `frontier` | function | frontier/2 |  |  |  |  |

| `select` | function | select/1 |  |  |  |  |

| `select` | function | select/3 |  |  |  |  |

| `storage_candidates` | function | storage_candidates/1 |  |  |  |  |

| `storage_candidates` | function | storage_candidates/1 |  |  |  |  |

| `storage_candidates` | function | storage_candidates/1 |  |  |  |  |


### AshR2RML.DfCM.CandidateSet

| `equivalent?` | function | equivalent?/3 |  |  |  |  |

| `narrow` | function | narrow/2 |  |  |  |  |

| `narrow` | function | narrow/2 |  |  |  |  |

| `normalize` | function | normalize/2 |  |  |  |  |

| `normalize_candidate` | function | normalize_candidate/1 |  |  |  |  |

| `normalize_candidate` | function | normalize_candidate/1 |  |  |  |  |

| `normalize_candidate` | function | normalize_candidate/1 |  |  |  |  |

| `require_nonempty` | function | require_nonempty/2 |  |  |  |  |

| `require_nonempty` | function | require_nonempty/2 |  |  |  |  |

| `require_selected` | function | require_selected/2 |  |  |  |  |

| `require_subset` | function | require_subset/3 |  |  |  |  |

| `select` | function | select/3 |  |  |  |  |


### AshR2RML.DfCM.Compilation


### AshR2RML.DfCM.Compiler

| `admit_receipt_reuse` | function | admit_receipt_reuse/2 |  |  |  |  |

| `attach_parity_witness` | function | attach_parity_witness/3 |  |  |  |  |

| `authorize_cutover` | function | authorize_cutover/2 |  |  |  |  |

| `bind_verification_environment` | function | bind_verification_environment/2 |  |  |  |  |

| `classify_file_error` | function | classify_file_error/1 |  |  |  |  |

| `classify_file_error` | function | classify_file_error/1 |  |  |  |  |

| `compile` | function | compile/1 |  |  |  |  |

| `cutover_ready?` | function | cutover_ready?/1 |  |  |  |  |

| `drift` | function | drift/2 |  |  |  |  |

| `envelope` | function | envelope/3 |  |  |  |  |

| `get` | function | get/3 |  |  |  |  |

| `incremental_plan` | function | incremental_plan/2 |  |  |  |  |

| `maybe_add` | function | maybe_add/3 |  |  |  |  |

| `maybe_add` | function | maybe_add/3 |  |  |  |  |

| `present_hash?` | function | present_hash?/1 |  |  |  |  |

| `receipt_reusable?` | function | receipt_reusable?/2 |  |  |  |  |

| `refresh` | function | refresh/1 |  |  |  |  |

| `session_identity` | function | session_identity/1 |  |  |  |  |


### AshR2RML.DfCM.IncrementalPlan


### AshR2RML.DfCM.IntegrityReceipt


### AshR2RML.DfCM.StorageProbe


### AshR2RML.Dsl.Class


### AshR2RML.Dsl.Graph


### AshR2RML.Dsl.KnowledgeHook


### AshR2RML.Dsl.Property


### AshR2RML.Dsl.Reference


### AshR2RML.Dsl.SparqlQuery


### AshR2RML.Dsl.Subject


### AshR2RML.Evidence

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical_ocel_event` | function | canonical_ocel_event/1 |  |  |  |  |

| `execution_id` | function | execution_id/1 |  |  |  |  |

| `execution_id` | function | execution_id/1 |  |  |  |  |

| `get` | function | get/2 |  |  |  |  |

| `get` | function | get/2 |  |  |  |  |

| `id` | function | id/1 |  |  |  |  |

| `id` | function | id/1 |  |  |  |  |

| `id` | function | id/1 |  |  |  |  |

| `id` | function | id/1 |  |  |  |  |

| `id` | function | id/1 |  |  |  |  |

| `normalize_e2o` | function | normalize_e2o/1 |  |  |  |  |

| `normalize_e2o` | function | normalize_e2o/1 |  |  |  |  |

| `normalize_run_object` | function | normalize_run_object/1 |  |  |  |  |

| `normalize_run_object` | function | normalize_run_object/1 |  |  |  |  |

| `ocel_trace_id` | function | ocel_trace_id/2 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |


### AshR2RML.Federation

| `admit_environment` | function | admit_environment/1 |  |  |  |  |

| `admit_environment` | function | admit_environment/1 |  |  |  |  |

| `compile_for_environments` | function | compile_for_environments/3 |  |  |  |  |

| `compile_for_environments` | function | compile_for_environments/3 |  |  |  |  |

| `compile_for_environments` | function | compile_for_environments/3 |  |  |  |  |


### AshR2RML.Federation.Environment


### AshR2RML.Federation.FederationReceipt


### AshR2RML.Formatter

| `extensions` | function | extensions/0 |  |  |  |  |

| `features` | function | features/1 |  |  |  |  |

| `format` | function | format/2 |  |  |  |  |


### AshR2RML.Fortune5.AshFactory

| `build_system_seed` | function | build_system_seed/1 |  |  |  |  |

| `compile_fortune5_bundle` | function | compile_fortune5_bundle/0 |  |  |  |  |

| `domain` | function | domain/0 |  |  |  |  |

| `render_fortune5_r2rml` | function | render_fortune5_r2rml/0 |  |  |  |  |

| `resources` | function | resources/0 |  |  |  |  |

| `types` | function | types/0 |  |  |  |  |


### AshR2RML.Fortune5.Calculations.UptimeSla

| `AshR2RML.Fortune5.Calculations.UptimeSla` | ash_resource |  |  |  |  |  |

| `calculate` | function | calculate/3 |  |  |  |  |


### AshR2RML.Fortune5.CloudRegion

| `AshR2RML.Fortune5.CloudRegion` | ash_resource |  |  |  |  |  |


### AshR2RML.Fortune5.Cluster

| `AshR2RML.Fortune5.Cluster` | ash_resource |  |  |  |  |  |


### AshR2RML.Fortune5.CredentialGrant

| `AshR2RML.Fortune5.CredentialGrant` | ash_resource |  |  |  |  |  |


### AshR2RML.Fortune5.DeploymentPlan

| `AshR2RML.Fortune5.DeploymentPlan` | ash_resource |  |  |  |  |  |


### AshR2RML.Fortune5.DeploymentPlanService

| `AshR2RML.Fortune5.DeploymentPlanService` | ash_resource |  |  |  |  |  |


### AshR2RML.Fortune5.Domain


### AshR2RML.Fortune5.EvidenceEngine

| `build_complete_evidence_bundle` | function | build_complete_evidence_bundle/1 |  |  |  |  |

| `build_dcat_catalog` | function | build_dcat_catalog/1 |  |  |  |  |

| `build_earl_assertion` | function | build_earl_assertion/1 |  |  |  |  |

| `build_prov_lineage` | function | build_prov_lineage/1 |  |  |  |  |

| `build_sosa_observation` | function | build_sosa_observation/1 |  |  |  |  |

| `emit_ocel2_multigraph` | function | emit_ocel2_multigraph/1 |  |  |  |  |

| `random_id` | function | random_id/0 |  |  |  |  |

| `standard_prefixes` | function | standard_prefixes/0 |  |  |  |  |


### AshR2RML.Fortune5.IncidentTicket

| `AshR2RML.Fortune5.IncidentTicket` | ash_resource |  |  |  |  |  |


### AshR2RML.Fortune5.LedgerAccount

| `AshR2RML.Fortune5.LedgerAccount` | ash_resource |  |  |  |  |  |


### AshR2RML.Fortune5.PaymentGateway

| `AshR2RML.Fortune5.PaymentGateway` | ash_resource |  |  |  |  |  |


### AshR2RML.Fortune5.SagaOrchestrator

| `events` | function | events/0 |  |  |  |  |

| `record_event` | function | record_event/1 |  |  |  |  |

| `reset_events` | function | reset_events/0 |  |  |  |  |

| `run_blue_green` | function | run_blue_green/2 |  |  |  |  |

| `run_credential_rotation` | function | run_credential_rotation/2 |  |  |  |  |

| `run_disaster_recovery` | function | run_disaster_recovery/2 |  |  |  |  |


### AshR2RML.Fortune5.SagaOrchestrator.BlueGreenDeploymentReactor


### AshR2RML.Fortune5.SagaOrchestrator.CredentialRotationReactor


### AshR2RML.Fortune5.SagaOrchestrator.DisasterRecoveryFailoverReactor


### AshR2RML.Fortune5.SagaOrchestrator.ExecutionRecorder

| `record` | function | record/1 |  |  |  |  |

| `reset` | function | reset/0 |  |  |  |  |

| `start_link` | function | start_link/1 |  |  |  |  |

| `stop` | function | stop/0 |  |  |  |  |


### AshR2RML.Fortune5.SagaOrchestrator.Steps.DrainTrafficStep

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `undo` | function | undo/4 |  |  |  |  |


### AshR2RML.Fortune5.SagaOrchestrator.Steps.FailoverDnsStep

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `undo` | function | undo/4 |  |  |  |  |


### AshR2RML.Fortune5.SagaOrchestrator.Steps.GenerateNewKeyStep

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `undo` | function | undo/4 |  |  |  |  |


### AshR2RML.Fortune5.SagaOrchestrator.Steps.IsolateRegionStep

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `undo` | function | undo/4 |  |  |  |  |


### AshR2RML.Fortune5.SagaOrchestrator.Steps.PromoteSecondaryDbStep

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `undo` | function | undo/4 |  |  |  |  |


### AshR2RML.Fortune5.SagaOrchestrator.Steps.ProvisionGreenNodeStep

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `undo` | function | undo/4 |  |  |  |  |


### AshR2RML.Fortune5.SagaOrchestrator.Steps.RevokeOldKeysStep

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `undo` | function | undo/4 |  |  |  |  |


### AshR2RML.Fortune5.SagaOrchestrator.Steps.RolloutDualAuthStep

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `undo` | function | undo/4 |  |  |  |  |


### AshR2RML.Fortune5.SagaOrchestrator.Steps.SwitchDnsRoutingStep

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `undo` | function | undo/4 |  |  |  |  |


### AshR2RML.Fortune5.SagaOrchestrator.Steps.ValidateCredentialsStep

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `undo` | function | undo/4 |  |  |  |  |


### AshR2RML.Fortune5.SagaOrchestrator.Steps.VerifyHealthStep

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `undo` | function | undo/4 |  |  |  |  |


### AshR2RML.Fortune5.SagaOrchestrator.Steps.VerifyReplicationStep

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `undo` | function | undo/4 |  |  |  |  |


### AshR2RML.Fortune5.ServiceInstance

| `AshR2RML.Fortune5.ServiceInstance` | ash_resource |  |  |  |  |  |


### AshR2RML.Fortune5.Types.CriticalityEnum

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `dump_to_embedded` | function | dump_to_embedded/2 |  |  |  |  |

| `dump_to_embedded` | function | dump_to_embedded/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `from_rdf_lexical` | function | from_rdf_lexical/1 |  |  |  |  |

| `storage_type` | function | storage_type/1 |  |  |  |  |

| `to_rdf_lexical` | function | to_rdf_lexical/1 |  |  |  |  |

| `values` | function | values/0 |  |  |  |  |


### AshR2RML.Fortune5.Types.CurrencyAmount

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `dump_to_embedded` | function | dump_to_embedded/2 |  |  |  |  |

| `dump_to_embedded` | function | dump_to_embedded/2 |  |  |  |  |

| `dump_to_embedded` | function | dump_to_embedded/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `from_rdf_lexical` | function | from_rdf_lexical/1 |  |  |  |  |

| `storage_type` | function | storage_type/1 |  |  |  |  |

| `to_decimal` | function | to_decimal/1 |  |  |  |  |

| `to_decimal` | function | to_decimal/1 |  |  |  |  |

| `to_decimal` | function | to_decimal/1 |  |  |  |  |

| `to_decimal` | function | to_decimal/1 |  |  |  |  |

| `to_decimal` | function | to_decimal/1 |  |  |  |  |

| `to_rdf_lexical` | function | to_rdf_lexical/1 |  |  |  |  |

| `to_rdf_lexical` | function | to_rdf_lexical/1 |  |  |  |  |


### AshR2RML.Fortune5.Types.IPAddressRange

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `dump_to_embedded` | function | dump_to_embedded/2 |  |  |  |  |

| `dump_to_embedded` | function | dump_to_embedded/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `from_rdf_lexical` | function | from_rdf_lexical/1 |  |  |  |  |

| `parse_ip` | function | parse_ip/1 |  |  |  |  |

| `storage_type` | function | storage_type/1 |  |  |  |  |

| `to_rdf_lexical` | function | to_rdf_lexical/1 |  |  |  |  |

| `valid_cidr?` | function | valid_cidr?/1 |  |  |  |  |


### AshR2RML.FrontierEvidence

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `evaluation_execution` | function | evaluation_execution/1 |  |  |  |  |

| `evaluation_execution` | function | evaluation_execution/1 |  |  |  |  |

| `evaluation_execution` | function | evaluation_execution/1 |  |  |  |  |

| `evaluation_execution` | function | evaluation_execution/1 |  |  |  |  |

| `evaluation_observation_count` | function | evaluation_observation_count/1 |  |  |  |  |

| `evaluation_observation_count` | function | evaluation_observation_count/1 |  |  |  |  |

| `evaluation_observation_count` | function | evaluation_observation_count/1 |  |  |  |  |

| `evaluation_observation_count` | function | evaluation_observation_count/1 |  |  |  |  |

| `evaluation_observation_state` | function | evaluation_observation_state/2 |  |  |  |  |

| `evaluation_observation_state` | function | evaluation_observation_state/2 |  |  |  |  |

| `evidence_refusal` | function | evidence_refusal/4 |  |  |  |  |

| `fingerprint` | function | fingerprint/1 |  |  |  |  |

| `from_knowledge_hooks` | function | from_knowledge_hooks/4 |  |  |  |  |

| `from_knowledge_hooks` | function | from_knowledge_hooks/4 |  |  |  |  |

| `from_knowledge_hooks` | function | from_knowledge_hooks/4 |  |  |  |  |

| `inspect_type` | function | inspect_type/1 |  |  |  |  |

| `inspect_type` | function | inspect_type/1 |  |  |  |  |

| `producer_head` | function | producer_head/1 |  |  |  |  |

| `refusal` | function | refusal/3 |  |  |  |  |

| `reject_duplicate` | function | reject_duplicate/4 |  |  |  |  |

| `replay_matches?` | function | replay_matches?/3 |  |  |  |  |

| `replay_matches?` | function | replay_matches?/3 |  |  |  |  |

| `sha256?` | function | sha256?/1 |  |  |  |  |

| `sha256_prefixed?` | function | sha256_prefixed?/1 |  |  |  |  |

| `standing` | function | standing/1 |  |  |  |  |

| `trigger_refusal` | function | trigger_refusal/3 |  |  |  |  |

| `validate_evaluation` | function | validate_evaluation/0 |  |  |  |  |

| `validate_evaluation` | function | validate_evaluation/3 |  |  |  |  |

| `validate_evaluation_receipt` | function | validate_evaluation_receipt/5 |  |  |  |  |

| `validate_evaluations` | function | validate_evaluations/2 |  |  |  |  |

| `validate_evaluations` | function | validate_evaluations/2 |  |  |  |  |

| `validate_external_trigger_link` | function | validate_external_trigger_link/4 |  |  |  |  |

| `validate_intent` | function | validate_intent/3 |  |  |  |  |

| `validate_intent` | function | validate_intent/0 |  |  |  |  |

| `validate_intent` | function | validate_intent/3 |  |  |  |  |

| `validate_observation` | function | validate_observation/2 |  |  |  |  |

| `validate_observation` | function | validate_observation/2 |  |  |  |  |

| `validate_observations` | function | validate_observations/1 |  |  |  |  |

| `validate_observations` | function | validate_observations/1 |  |  |  |  |

| `validate_options` | function | validate_options/1 |  |  |  |  |

| `validate_trigger_receipt` | function | validate_trigger_receipt/3 |  |  |  |  |

| `validate_trigger_receipt` | function | validate_trigger_receipt/3 |  |  |  |  |

| `validate_trigger_receipts` | function | validate_trigger_receipts/2 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |


### AshR2RML.Functions.GeofDistance

| `args` | function | args/0 |  |  |  |  |

| `returns` | function | returns/0 |  |  |  |  |


### AshR2RML.Functions.GeofSfIntersects

| `args` | function | args/0 |  |  |  |  |

| `returns` | function | returns/0 |  |  |  |  |


### AshR2RML.Functions.VecCosineSimilarity

| `args` | function | args/0 |  |  |  |  |

| `returns` | function | returns/0 |  |  |  |  |


### AshR2RML.Generated.SemanticSchemaMigration

| `change` | function | change/0 |  |  |  |  |


### AshR2RML.Ggen

| `compile_api_bundle` | function | compile_api_bundle/2 |  |  |  |  |

| `compile_bundle` | function | compile_bundle/2 |  |  |  |  |

| `compile_jsonld_bundle` | function | compile_jsonld_bundle/2 |  |  |  |  |

| `compile_semantic_types_bundle` | function | compile_semantic_types_bundle/2 |  |  |  |  |

| `compile_turtle_bundle` | function | compile_turtle_bundle/2 |  |  |  |  |

| `encode_json` | function | encode_json/1 |  |  |  |  |

| `graphql_files` | function | graphql_files/2 |  |  |  |  |

| `json_key` | function | json_key/1 |  |  |  |  |

| `json_key` | function | json_key/1 |  |  |  |  |

| `json_key` | function | json_key/1 |  |  |  |  |

| `json_key` | function | json_key/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `verify_staged` | function | verify_staged/2 |  |  |  |  |


### AshR2RML.Ggen.KnowledgeHooks

| `bundle` | function | bundle/1 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile_turtle` | function | compile_turtle/2 |  |  |  |  |

| `encode_json` | function | encode_json/1 |  |  |  |  |

| `json_key` | function | json_key/1 |  |  |  |  |

| `json_key` | function | json_key/1 |  |  |  |  |

| `json_key` | function | json_key/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |


### AshR2RML.Ggen.Production

| `verify_staged` | function | verify_staged/2 |  |  |  |  |


### AshR2RML.Ggen.TTL

| `bundle` | function | bundle/1 |  |  |  |  |

| `bundle` | function | bundle/1 |  |  |  |  |

| `datatype_range` | function | datatype_range/1 |  |  |  |  |

| `datatype_range` | function | datatype_range/1 |  |  |  |  |

| `emit` | function | emit/1 |  |  |  |  |

| `ontology` | function | ontology/1 |  |  |  |  |

| `relationship_statements` | function | relationship_statements/2 |  |  |  |  |

| `resource_key` | function | resource_key/1 |  |  |  |  |

| `resource_key` | function | resource_key/1 |  |  |  |  |

| `scalar_statements` | function | scalar_statements/1 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `target_classes` | function | target_classes/2 |  |  |  |  |


### AshR2RML.GgenRuntime

| `contract` | function | contract/1 |  |  |  |  |

| `contract` | function | contract/1 |  |  |  |  |

| `digest` | function | digest/1 |  |  |  |  |

| `validate_authority` | function | validate_authority/1 |  |  |  |  |

| `validate_authority` | function | validate_authority/1 |  |  |  |  |

| `validate_subject` | function | validate_subject/1 |  |  |  |  |

| `validate_subject` | function | validate_subject/1 |  |  |  |  |


### AshR2RML.GgenRuntime.Audit

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |


### AshR2RML.GgenRuntime.Authority

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |


### AshR2RML.GgenRuntime.CacheContract

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |


### AshR2RML.GgenRuntime.Concurrency

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |


### AshR2RML.GgenRuntime.Config

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `digest` | function | digest/1 |  |  |  |  |


### AshR2RML.GgenRuntime.DataContract

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |


### AshR2RML.GgenRuntime.Deadline

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |


### AshR2RML.GgenRuntime.DomainError

| `normalize` | function | normalize/1 |  |  |  |  |

| `normalize` | function | normalize/1 |  |  |  |  |

| `normalize` | function | normalize/1 |  |  |  |  |


### AshR2RML.GgenRuntime.Eventing

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |


### AshR2RML.GgenRuntime.FaultIsolation

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |


### AshR2RML.GgenRuntime.FullIntegration

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |


### AshR2RML.GgenRuntime.Idempotency

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |


### AshR2RML.GgenRuntime.Integration

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `digest` | function | digest/1 |  |  |  |  |


### AshR2RML.GgenRuntime.Isolation

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |


### AshR2RML.GgenRuntime.Lifecycle

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |


### AshR2RML.GgenRuntime.Observability

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |


### AshR2RML.GgenRuntime.Persistence

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |


### AshR2RML.GgenRuntime.RateLimit

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |


### AshR2RML.GgenRuntime.ReactorContract

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |


### AshR2RML.GgenRuntime.Replay

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |


### AshR2RML.GgenRuntime.Resilience

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |


### AshR2RML.GgenRuntime.Security

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |


### AshR2RML.GgenRuntime.Subject

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |


### AshR2RML.GgenRuntime.Transport

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |


### AshR2RML.GrandExample.Domain


### AshR2RML.GrandExample.Hooks

| `cleanup_preflight` | function | cleanup_preflight/1 |  |  |  |  |

| `setup_preflight` | function | setup_preflight/3 |  |  |  |  |


### AshR2RML.GrandExample.Organization

| `AshR2RML.GrandExample.Organization` | ash_resource |  |  |  |  |  |


### AshR2RML.GrandExample.Person

| `AshR2RML.GrandExample.Person` | ash_resource |  |  |  |  |  |


### AshR2RML.GrandExample.PublishingReactor


### AshR2RML.GrandExample.SemanticManifest

| `AshR2RML.GrandExample.SemanticManifest` | ash_resource |  |  |  |  |  |


### AshR2RML.GrandExample.Shipment

| `AshR2RML.GrandExample.Shipment` | ash_resource |  |  |  |  |  |


### AshR2RML.GrandExample.SubReactors.InputVerifier


### AshR2RML.GrandExample.Types.SemVer

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `dump_to_embedded` | function | dump_to_embedded/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `storage_type` | function | storage_type/1 |  |  |  |  |

| `to_rdf_lexical` | function | to_rdf_lexical/1 |  |  |  |  |


### AshR2RML.GrandExample.Warehouse

| `AshR2RML.GrandExample.Warehouse` | ash_resource |  |  |  |  |  |


### AshR2RML.GrandExample.Wrappers

| `with_audit_span` | function | with_audit_span/4 |  |  |  |  |


### AshR2RML.GrandExample.ZachPostAgiReactor


### AshR2RML.Graphql


### AshR2RML.Graphql.Info

| `derived_queries` | function | derived_queries/1 |  |  |  |  |

| `domain` | function | domain/1 |  |  |  |  |

| `domain_enabled?` | function | domain_enabled?/1 |  |  |  |  |

| `domain_opt_enabled?` | function | domain_opt_enabled?/1 |  |  |  |  |

| `enabled?` | function | enabled?/1 |  |  |  |  |

| `resource_enabled?` | function | resource_enabled?/1 |  |  |  |  |


### AshR2RML.Graphql.MutationLeakError


### AshR2RML.Graphql.Schema


### AshR2RML.Graphql.Transformers.DeriveQueries

| `after?` | function | after?/1 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `before?` | function | before?/1 |  |  |  |  |

| `before?` | function | before?/1 |  |  |  |  |

| `before?` | function | before?/1 |  |  |  |  |

| `before?` | function | before?/1 |  |  |  |  |

| `before?` | function | before?/1 |  |  |  |  |

| `derive_type` | function | derive_type/1 |  |  |  |  |

| `paginate_with` | function | paginate_with/1 |  |  |  |  |

| `paginate_with` | function | paginate_with/1 |  |  |  |  |

| `paginate_with` | function | paginate_with/1 |  |  |  |  |

| `paginate_with` | function | paginate_with/1 |  |  |  |  |

| `project` | function | project/1 |  |  |  |  |

| `queries_for` | function | queries_for/3 |  |  |  |  |

| `query` | function | query/1 |  |  |  |  |

| `read_actions` | function | read_actions/1 |  |  |  |  |

| `resource?` | function | resource?/1 |  |  |  |  |

| `transform` | function | transform/1 |  |  |  |  |


### AshR2RML.Graphql.Verifiers.NoMutations

| `verify` | function | verify/1 |  |  |  |  |


### AshR2RML.GraphqlAutoProjection.Domain


### AshR2RML.GraphqlAutoProjection.Drone

| `AshR2RML.GraphqlAutoProjection.Drone` | ash_resource |  |  |  |  |  |


### AshR2RML.GraphqlAutoProjection.Robot

| `AshR2RML.GraphqlAutoProjection.Robot` | ash_resource |  |  |  |  |  |


### AshR2RML.GraphqlAutoProjection.Schema


### AshR2RML.GraphqlProjection.Domain


### AshR2RML.GraphqlProjection.Person

| `AshR2RML.GraphqlProjection.Person` | ash_resource |  |  |  |  |  |


### AshR2RML.GraphqlProjection.Schema


### AshR2RML.Ingestion

| `compile_turtle` | function | compile_turtle/2 |  |  |  |  |

| `from_graph` | function | from_graph/2 |  |  |  |  |

| `from_turtle` | function | from_turtle/2 |  |  |  |  |

| `identity_keys` | function | identity_keys/3 |  |  |  |  |

| `parse_identities` | function | parse_identities/3 |  |  |  |  |

| `parse_resource` | function | parse_resource/2 |  |  |  |  |

| `parse_resources` | function | parse_resources/2 |  |  |  |  |


### AshR2RML.Integrity.Canonical

| `binary_sha256` | function | binary_sha256/1 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `term` | function | term/1 |  |  |  |  |

| `term` | function | term/1 |  |  |  |  |

| `term` | function | term/1 |  |  |  |  |

| `term` | function | term/1 |  |  |  |  |

| `term` | function | term/1 |  |  |  |  |


### AshR2RML.Introspection

| `column` | function | column/2 |  |  |  |  |

| `extract_identities` | function | extract_identities/2 |  |  |  |  |

| `identities` | function | identities/2 |  |  |  |  |

| `identities` | function | identities/2 |  |  |  |  |

| `identities` | function | identities/2 |  |  |  |  |

| `infer_logical_table` | function | infer_logical_table/1 |  |  |  |  |

| `infer_logical_table_from_data_layer` | function | infer_logical_table_from_data_layer/1 |  |  |  |  |

| `infer_postgres_table` | function | infer_postgres_table/1 |  |  |  |  |

| `logical_table` | function | logical_table/2 |  |  |  |  |

| `many_to_many_metadata` | function | many_to_many_metadata/2 |  |  |  |  |

| `persisted_logical_table` | function | persisted_logical_table/1 |  |  |  |  |

| `relationship` | function | relationship/2 |  |  |  |  |

| `relationship_metadata` | function | relationship_metadata/2 |  |  |  |  |

| `simple_relationship_metadata` | function | simple_relationship_metadata/2 |  |  |  |  |

| `stable_subject_identity?` | function | stable_subject_identity?/2 |  |  |  |  |


### AshR2RML.Introspection.Manifest

| `fetch_resource` | function | fetch_resource/2 |  |  |  |  |

| `generate` | function | generate/1 |  |  |  |  |

| `manifest_result` | function | manifest_result/1 |  |  |  |  |

| `resource_lookup` | function | resource_lookup/1 |  |  |  |  |


### AshR2RML.JSONLD

| `admit_contexts` | function | admit_contexts/2 |  |  |  |  |

| `compact` | function | compact/3 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `context_urls` | function | context_urls/1 |  |  |  |  |

| `context_urls` | function | context_urls/1 |  |  |  |  |

| `context_urls` | function | context_urls/1 |  |  |  |  |

| `decode_document` | function | decode_document/1 |  |  |  |  |

| `decode_document` | function | decode_document/1 |  |  |  |  |

| `decode_document` | function | decode_document/1 |  |  |  |  |

| `encode_rdf` | function | encode_rdf/2 |  |  |  |  |

| `expand` | function | expand/2 |  |  |  |  |

| `ingest` | function | ingest/2 |  |  |  |  |

| `json_options` | function | json_options/1 |  |  |  |  |

| `jsonld_error` | function | jsonld_error/2 |  |  |  |  |

| `maybe_compact` | function | maybe_compact/2 |  |  |  |  |

| `remote_contexts` | function | remote_contexts/1 |  |  |  |  |

| `remote_contexts` | function | remote_contexts/1 |  |  |  |  |

| `remote_contexts` | function | remote_contexts/1 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `to_rdf` | function | to_rdf/2 |  |  |  |  |


### AshR2RML.KnowledgeHook


### AshR2RML.KnowledgeHook.Ash

| `action_name` | function | action_name/1 |  |  |  |  |

| `action_name` | function | action_name/1 |  |  |  |  |

| `action_name` | function | action_name/1 |  |  |  |  |

| `action_type` | function | action_type/2 |  |  |  |  |

| `ash_pattern` | function | ash_pattern/1 |  |  |  |  |

| `ash_pattern` | function | ash_pattern/1 |  |  |  |  |

| `ash_source` | function | ash_source/1 |  |  |  |  |

| `ash_source` | function | ash_source/1 |  |  |  |  |

| `atomic_keys` | function | atomic_keys/1 |  |  |  |  |

| `atomic_keys` | function | atomic_keys/1 |  |  |  |  |

| `atomic_keys` | function | atomic_keys/1 |  |  |  |  |

| `attribute_delta` | function | attribute_delta/4 |  |  |  |  |

| `build_receipt` | function | build_receipt/2 |  |  |  |  |

| `canonical_pattern` | function | canonical_pattern/1 |  |  |  |  |

| `canonical_pattern` | function | canonical_pattern/1 |  |  |  |  |

| `canonical_pattern` | function | canonical_pattern/1 |  |  |  |  |

| `canonical_pattern` | function | canonical_pattern/1 |  |  |  |  |

| `changed_attribute_names` | function | changed_attribute_names/1 |  |  |  |  |

| `changed_relationship_names` | function | changed_relationship_names/1 |  |  |  |  |

| `evaluate` | function | evaluate/3 |  |  |  |  |

| `existing_atom_key` | function | existing_atom_key/2 |  |  |  |  |

| `explicit_trigger_receipt` | function | explicit_trigger_receipt/4 |  |  |  |  |

| `field_match?` | function | field_match?/3 |  |  |  |  |

| `field_match?` | function | field_match?/3 |  |  |  |  |

| `get` | function | get/3 |  |  |  |  |

| `inspect_type` | function | inspect_type/1 |  |  |  |  |

| `inspect_type` | function | inspect_type/1 |  |  |  |  |

| `key_string` | function | key_string/1 |  |  |  |  |

| `key_string` | function | key_string/1 |  |  |  |  |

| `key_string` | function | key_string/1 |  |  |  |  |

| `match_receipts` | function | match_receipts/3 |  |  |  |  |

| `matches?` | function | matches?/3 |  |  |  |  |

| `matches?` | function | matches?/3 |  |  |  |  |

| `module_name` | function | module_name/1 |  |  |  |  |

| `module_name` | function | module_name/1 |  |  |  |  |

| `module_name` | function | module_name/1 |  |  |  |  |

| `normalize_atomish` | function | normalize_atomish/1 |  |  |  |  |

| `normalize_atomish` | function | normalize_atomish/1 |  |  |  |  |

| `normalize_atomish` | function | normalize_atomish/1 |  |  |  |  |

| `normalize_atomish` | function | normalize_atomish/1 |  |  |  |  |

| `normalize_name` | function | normalize_name/1 |  |  |  |  |

| `normalize_name` | function | normalize_name/1 |  |  |  |  |

| `normalize_name` | function | normalize_name/1 |  |  |  |  |

| `normalize_name` | function | normalize_name/1 |  |  |  |  |

| `normalize_resource` | function | normalize_resource/1 |  |  |  |  |

| `normalize_resource` | function | normalize_resource/1 |  |  |  |  |

| `normalize_resource` | function | normalize_resource/1 |  |  |  |  |

| `observe` | function | observe/1 |  |  |  |  |

| `observe` | function | observe/1 |  |  |  |  |

| `observe` | function | observe/1 |  |  |  |  |

| `observe` | function | observe/1 |  |  |  |  |

| `observe` | function | observe/1 |  |  |  |  |

| `observe_many` | function | observe_many/1 |  |  |  |  |

| `observe_notification` | function | observe_notification/1 |  |  |  |  |

| `observe_notification` | function | observe_notification/1 |  |  |  |  |

| `observe_notification` | function | observe_notification/1 |  |  |  |  |

| `primary_key` | function | primary_key/2 |  |  |  |  |

| `primary_key` | function | primary_key/2 |  |  |  |  |

| `primary_key` | function | primary_key/2 |  |  |  |  |

| `projection` | function | projection/1 |  |  |  |  |

| `record_value` | function | record_value/2 |  |  |  |  |

| `record_value` | function | record_value/2 |  |  |  |  |

| `record_value` | function | record_value/2 |  |  |  |  |

| `refusal` | function | refusal/3 |  |  |  |  |

| `stable_scalar` | function | stable_scalar/1 |  |  |  |  |

| `stable_scalar` | function | stable_scalar/1 |  |  |  |  |

| `stable_scalar` | function | stable_scalar/1 |  |  |  |  |

| `stable_value` | function | stable_value/1 |  |  |  |  |

| `stable_value` | function | stable_value/1 |  |  |  |  |

| `stable_value` | function | stable_value/1 |  |  |  |  |

| `stable_value` | function | stable_value/1 |  |  |  |  |

| `stable_value` | function | stable_value/1 |  |  |  |  |

| `stable_value` | function | stable_value/1 |  |  |  |  |

| `stable_value` | function | stable_value/1 |  |  |  |  |

| `stable_value` | function | stable_value/1 |  |  |  |  |

| `stable_value` | function | stable_value/1 |  |  |  |  |

| `stable_value` | function | stable_value/1 |  |  |  |  |

| `subset_match?` | function | subset_match?/2 |  |  |  |  |

| `subset_match?` | function | subset_match?/2 |  |  |  |  |

| `transition_match` | function | transition_match/3 |  |  |  |  |

| `transition_match` | function | transition_match/3 |  |  |  |  |

| `trigger_receipts` | function | trigger_receipts/2 |  |  |  |  |

| `validate_pattern` | function | validate_pattern/3 |  |  |  |  |

| `validate_transition` | function | validate_transition/3 |  |  |  |  |

| `validate_transition` | function | validate_transition/3 |  |  |  |  |

| `validate_transition` | function | validate_transition/3 |  |  |  |  |


### AshR2RML.KnowledgeHook.Ash.ObservationReceipt


### AshR2RML.KnowledgeHook.Construct


### AshR2RML.KnowledgeHook.Datalog

| `admit_rule` | function | admit_rule/1 |  |  |  |  |

| `admit_rule` | function | admit_rule/1 |  |  |  |  |

| `evaluate` | function | evaluate/3 |  |  |  |  |

| `evaluate` | function | evaluate/3 |  |  |  |  |

| `evaluate` | function | evaluate/3 |  |  |  |  |

| `parse_body` | function | parse_body/2 |  |  |  |  |

| `parse_head_vars` | function | parse_head_vars/2 |  |  |  |  |

| `split_rule` | function | split_rule/1 |  |  |  |  |


### AshR2RML.KnowledgeHook.Definition


### AshR2RML.KnowledgeHook.Dispatcher

| `notify` | function | notify/1 |  |  |  |  |

| `safe_observe` | function | safe_observe/2 |  |  |  |  |


### AshR2RML.KnowledgeHook.Dsl

| `section` | function | section/0 |  |  |  |  |


### AshR2RML.KnowledgeHook.Evaluation


### AshR2RML.KnowledgeHook.EvaluationReceipt


### AshR2RML.KnowledgeHook.Info

| `hooks` | function | hooks/1 |  |  |  |  |


### AshR2RML.KnowledgeHook.Ingestion

| `from_turtle` | function | from_turtle/2 |  |  |  |  |


### AshR2RML.KnowledgeHook.Intent


### AshR2RML.KnowledgeHook.Observation

| `from_notification` | function | from_notification/1 |  |  |  |  |


### AshR2RML.KnowledgeHook.Observation


### AshR2RML.KnowledgeHook.Plan


### AshR2RML.KnowledgeHook.Predicate


### AshR2RML.KnowledgeHook.Promotion

| `brce_request` | function | brce_request/2 |  |  |  |  |

| `candidate_boundary` | function | candidate_boundary/1 |  |  |  |  |

| `cognition_elimination_rate` | function | cognition_elimination_rate/2 |  |  |  |  |

| `cognition_elimination_rate` | function | cognition_elimination_rate/2 |  |  |  |  |

| `cognition_elimination_rate` | function | cognition_elimination_rate/2 |  |  |  |  |

| `evaluate` | function | evaluate/3 |  |  |  |  |

| `evaluate` | function | evaluate/3 |  |  |  |  |

| `evaluate` | function | evaluate/3 |  |  |  |  |

| `evidence_envelope` | function | evidence_envelope/2 |  |  |  |  |

| `evidence_identity` | function | evidence_identity/1 |  |  |  |  |

| `evidence_quality` | function | evidence_quality/1 |  |  |  |  |

| `minimum_evidence` | function | minimum_evidence/3 |  |  |  |  |

| `refusal` | function | refusal/3 |  |  |  |  |


### AshR2RML.KnowledgeHook.Promotion.Candidate


### AshR2RML.KnowledgeHook.Promotion.Evidence


### AshR2RML.KnowledgeHook.Promotion.Receipt


### AshR2RML.KnowledgeHook.RDF

| `from_graph` | function | from_graph/2 |  |  |  |  |

| `from_turtle` | function | from_turtle/2 |  |  |  |  |

| `native_hook_graph?` | function | native_hook_graph?/1 |  |  |  |  |

| `parse_hook` | function | parse_hook/2 |  |  |  |  |

| `require_construct_ceiling` | function | require_construct_ceiling/3 |  |  |  |  |

| `require_receipt_policy` | function | require_receipt_policy/3 |  |  |  |  |


### AshR2RML.KnowledgeHook.ReceiptPolicy


### AshR2RML.KnowledgeHook.SHACL

| `admit_shapes_graph` | function | admit_shapes_graph/1 |  |  |  |  |

| `admit_shapes_graph` | function | admit_shapes_graph/1 |  |  |  |  |

| `admit_shapes_graph` | function | admit_shapes_graph/1 |  |  |  |  |

| `class_violations` | function | class_violations/6 |  |  |  |  |

| `class_violations` | function | class_violations/6 |  |  |  |  |

| `conforms` | function | conforms/3 |  |  |  |  |

| `conforms` | function | conforms/3 |  |  |  |  |

| `datatype_violations` | function | datatype_violations/5 |  |  |  |  |

| `datatype_violations` | function | datatype_violations/5 |  |  |  |  |

| `has_type?` | function | has_type?/3 |  |  |  |  |

| `index_statements` | function | index_statements/1 |  |  |  |  |

| `literal_datatype_matches?` | function | literal_datatype_matches?/2 |  |  |  |  |

| `literal_datatype_matches?` | function | literal_datatype_matches?/2 |  |  |  |  |

| `literal_datatype_matches?` | function | literal_datatype_matches?/2 |  |  |  |  |

| `literal_datatype_matches?` | function | literal_datatype_matches?/2 |  |  |  |  |

| `literal_datatype_matches?` | function | literal_datatype_matches?/2 |  |  |  |  |

| `max_count_violation` | function | max_count_violation/5 |  |  |  |  |

| `max_count_violation` | function | max_count_violation/5 |  |  |  |  |

| `min_count_violation` | function | min_count_violation/5 |  |  |  |  |

| `min_count_violation` | function | min_count_violation/5 |  |  |  |  |

| `objects` | function | objects/3 |  |  |  |  |

| `pattern_violations` | function | pattern_violations/5 |  |  |  |  |

| `pattern_violations` | function | pattern_violations/5 |  |  |  |  |

| `property_shapes` | function | property_shapes/2 |  |  |  |  |

| `property_violations` | function | property_violations/4 |  |  |  |  |

| `shapes_by_subject` | function | shapes_by_subject/1 |  |  |  |  |

| `single` | function | single/1 |  |  |  |  |

| `single` | function | single/1 |  |  |  |  |

| `statement3` | function | statement3/1 |  |  |  |  |

| `statement3` | function | statement3/1 |  |  |  |  |

| `targeted?` | function | targeted?/3 |  |  |  |  |

| `targeted?` | function | targeted?/3 |  |  |  |  |

| `term_string` | function | term_string/1 |  |  |  |  |

| `term_string` | function | term_string/1 |  |  |  |  |

| `term_value` | function | term_value/1 |  |  |  |  |

| `to_integer` | function | to_integer/1 |  |  |  |  |

| `to_integer` | function | to_integer/1 |  |  |  |  |

| `to_integer` | function | to_integer/1 |  |  |  |  |

| `violation` | function | violation/5 |  |  |  |  |


### AshR2RML.KnowledgeHook.Scheduler

| `all_dependencies_exist` | function | all_dependencies_exist/2 |  |  |  |  |

| `do_schedule` | function | do_schedule/3 |  |  |  |  |

| `schedule` | function | schedule/1 |  |  |  |  |

| `unique_ids` | function | unique_ids/1 |  |  |  |  |


### AshR2RML.KnowledgeHook.Spec

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical_predicate` | function | canonical_predicate/1 |  |  |  |  |

| `dependencies` | function | dependencies/1 |  |  |  |  |

| `from_definition` | function | from_definition/1 |  |  |  |  |

| `from_plan` | function | from_plan/1 |  |  |  |  |

| `observation_projection` | function | observation_projection/1 |  |  |  |  |

| `projection` | function | projection/1 |  |  |  |  |

| `provenance_value` | function | provenance_value/3 |  |  |  |  |

| `validate_dependencies` | function | validate_dependencies/2 |  |  |  |  |


### AshR2RML.KnowledgeHook.Target

| `ash_action` | function | ash_action/3 |  |  |  |  |

| `from_intent` | function | from_intent/1 |  |  |  |  |

| `inert?` | function | inert?/1 |  |  |  |  |

| `inert?` | function | inert?/1 |  |  |  |  |

| `inert?` | function | inert?/1 |  |  |  |  |

| `inert?` | function | inert?/1 |  |  |  |  |

| `inert?` | function | inert?/1 |  |  |  |  |

| `inert?` | function | inert?/1 |  |  |  |  |

| `new` | function | new/4 |  |  |  |  |

| `normalize_kind` | function | normalize_kind/1 |  |  |  |  |

| `normalize_kind` | function | normalize_kind/1 |  |  |  |  |

| `normalize_kind` | function | normalize_kind/1 |  |  |  |  |

| `normalize_kind` | function | normalize_kind/1 |  |  |  |  |

| `normalize_kind` | function | normalize_kind/1 |  |  |  |  |

| `normalize_kind` | function | normalize_kind/1 |  |  |  |  |

| `normalize_kind` | function | normalize_kind/1 |  |  |  |  |

| `normalize_kind` | function | normalize_kind/1 |  |  |  |  |

| `normalize_kind` | function | normalize_kind/1 |  |  |  |  |

| `oban` | function | oban/3 |  |  |  |  |

| `projection` | function | projection/1 |  |  |  |  |

| `reactor` | function | reactor/2 |  |  |  |  |

| `require_unauthorized` | function | require_unauthorized/1 |  |  |  |  |

| `require_unauthorized` | function | require_unauthorized/1 |  |  |  |  |

| `stable_name` | function | stable_name/1 |  |  |  |  |

| `stable_name` | function | stable_name/1 |  |  |  |  |

| `stable_name` | function | stable_name/1 |  |  |  |  |

| `state_transition` | function | state_transition/3 |  |  |  |  |


### AshR2RML.KnowledgeHook.Transformers.RegisterDispatcher

| `after?` | function | after?/1 |  |  |  |  |

| `before?` | function | before?/1 |  |  |  |  |

| `transform` | function | transform/1 |  |  |  |  |


### AshR2RML.KnowledgeHook.Trigger


### AshR2RML.KnowledgeHookDslSectionSharing.Domain


### AshR2RML.KnowledgeHookDslSectionSharing.ResourceExtWidget

| `AshR2RML.KnowledgeHookDslSectionSharing.ResourceExtWidget` | ash_resource |  |  |  |  |  |


### AshR2RML.KnowledgeHooks

| `admit` | function | admit/2 |  |  |  |  |

| `admit` | function | admit/2 |  |  |  |  |

| `admit` | function | admit/2 |  |  |  |  |

| `ambient_actuation?` | function | ambient_actuation?/1 |  |  |  |  |

| `ambiguous_property` | function | ambiguous_property/3 |  |  |  |  |

| `boolean_result` | function | boolean_result/2 |  |  |  |  |

| `boolean_result` | function | boolean_result/2 |  |  |  |  |

| `bound_result` | function | bound_result/4 |  |  |  |  |

| `bound_result` | function | bound_result/4 |  |  |  |  |

| `bound_result` | function | bound_result/4 |  |  |  |  |

| `bound_result` | function | bound_result/4 |  |  |  |  |

| `build_evaluation` | function | build_evaluation/5 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical_definition` | function | canonical_definition/1 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `construct_intent` | function | construct_intent/2 |  |  |  |  |

| `current_opts` | function | current_opts/1 |  |  |  |  |

| `evaluate` | function | evaluate/2 |  |  |  |  |

| `evaluate_hook` | function | evaluate_hook/3 |  |  |  |  |

| `evaluate_hook` | function | evaluate_hook/0 |  |  |  |  |

| `evaluate_hook` | function | evaluate_hook/0 |  |  |  |  |

| `evaluate_hook` | function | evaluate_hook/3 |  |  |  |  |

| `evaluate_hook` | function | evaluate_hook/3 |  |  |  |  |

| `evaluate_hook` | function | evaluate_hook/0 |  |  |  |  |

| `evaluate_hook` | function | evaluate_hook/0 |  |  |  |  |

| `evaluation_steps` | function | evaluation_steps/2 |  |  |  |  |

| `evaluation_steps` | function | evaluation_steps/2 |  |  |  |  |

| `evaluation_steps` | function | evaluation_steps/2 |  |  |  |  |

| `evaluation_steps` | function | evaluation_steps/2 |  |  |  |  |

| `evaluation_steps` | function | evaluation_steps/2 |  |  |  |  |

| `evaluation_steps` | function | evaluation_steps/2 |  |  |  |  |

| `evaluation_steps` | function | evaluation_steps/2 |  |  |  |  |

| `evaluation_steps` | function | evaluation_steps/2 |  |  |  |  |

| `execute_query` | function | execute_query/2 |  |  |  |  |

| `external_trigger_witness` | function | external_trigger_witness/2 |  |  |  |  |

| `extract_time_field_values` | function | extract_time_field_values/3 |  |  |  |  |

| `fetch_evaluated_at` | function | fetch_evaluated_at/2 |  |  |  |  |

| `from_graph` | function | from_graph/2 |  |  |  |  |

| `from_turtle` | function | from_turtle/2 |  |  |  |  |

| `get` | function | get/3 |  |  |  |  |

| `graph_sha256` | function | graph_sha256/1 |  |  |  |  |

| `index_statements` | function | index_statements/1 |  |  |  |  |

| `inert_term?` | function | inert_term?/1 |  |  |  |  |

| `inert_term?` | function | inert_term?/1 |  |  |  |  |

| `inert_term?` | function | inert_term?/1 |  |  |  |  |

| `inert_term?` | function | inert_term?/1 |  |  |  |  |

| `inert_term?` | function | inert_term?/1 |  |  |  |  |

| `inert_term?` | function | inert_term?/1 |  |  |  |  |

| `missing_property` | function | missing_property/2 |  |  |  |  |

| `normalize_bound_predicate` | function | normalize_bound_predicate/4 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_datalog_predicate` | function | normalize_datalog_predicate/2 |  |  |  |  |

| `normalize_definition` | function | normalize_definition/1 |  |  |  |  |

| `normalize_definition` | function | normalize_definition/1 |  |  |  |  |

| `normalize_definitions` | function | normalize_definitions/1 |  |  |  |  |

| `normalize_intent` | function | normalize_intent/2 |  |  |  |  |

| `normalize_intent` | function | normalize_intent/2 |  |  |  |  |

| `normalize_intent` | function | normalize_intent/2 |  |  |  |  |

| `normalize_intent` | function | normalize_intent/2 |  |  |  |  |

| `normalize_predicate` | function | normalize_predicate/3 |  |  |  |  |

| `normalize_predicate` | function | normalize_predicate/3 |  |  |  |  |

| `normalize_predicate` | function | normalize_predicate/3 |  |  |  |  |

| `normalize_predicate` | function | normalize_predicate/3 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_shacl_focus` | function | normalize_shacl_focus/2 |  |  |  |  |

| `normalize_shacl_focus` | function | normalize_shacl_focus/2 |  |  |  |  |

| `normalize_shacl_focus` | function | normalize_shacl_focus/2 |  |  |  |  |

| `normalize_shacl_predicate` | function | normalize_shacl_predicate/2 |  |  |  |  |

| `normalize_temporal_window_predicate` | function | normalize_temporal_window_predicate/3 |  |  |  |  |

| `normalize_trigger_type` | function | normalize_trigger_type/1 |  |  |  |  |

| `normalize_trigger_type` | function | normalize_trigger_type/1 |  |  |  |  |

| `normalize_trigger_type` | function | normalize_trigger_type/1 |  |  |  |  |

| `normalize_trigger_type` | function | normalize_trigger_type/1 |  |  |  |  |

| `normalize_trigger_type` | function | normalize_trigger_type/1 |  |  |  |  |

| `normalize_trigger_type` | function | normalize_trigger_type/1 |  |  |  |  |

| `normalize_trigger_type` | function | normalize_trigger_type/1 |  |  |  |  |

| `normalize_trigger_type` | function | normalize_trigger_type/1 |  |  |  |  |

| `normalize_trigger_type` | function | normalize_trigger_type/1 |  |  |  |  |

| `normalize_trigger_type` | function | normalize_trigger_type/1 |  |  |  |  |

| `objects` | function | objects/3 |  |  |  |  |

| `optional_literal` | function | optional_literal/3 |  |  |  |  |

| `optional_value` | function | optional_value/3 |  |  |  |  |

| `parse_gitvan_hook` | function | parse_gitvan_hook/2 |  |  |  |  |

| `parse_knhk_hook` | function | parse_knhk_hook/2 |  |  |  |  |

| `parse_many` | function | parse_many/2 |  |  |  |  |

| `parse_numeric` | function | parse_numeric/2 |  |  |  |  |

| `parse_xsd_datetime` | function | parse_xsd_datetime/1 |  |  |  |  |

| `parse_xsd_datetime` | function | parse_xsd_datetime/1 |  |  |  |  |

| `parse_xsd_datetime` | function | parse_xsd_datetime/1 |  |  |  |  |

| `present_ambient_keys` | function | present_ambient_keys/1 |  |  |  |  |

| `previous_opts` | function | previous_opts/1 |  |  |  |  |

| `projection` | function | projection/1 |  |  |  |  |

| `projection_definition` | function | projection_definition/1 |  |  |  |  |

| `require_knhk_receipt` | function | require_knhk_receipt/3 |  |  |  |  |

| `required_literal` | function | required_literal/4 |  |  |  |  |

| `required_object` | function | required_object/4 |  |  |  |  |

| `shacl_data` | function | shacl_data/1 |  |  |  |  |

| `statement3` | function | statement3/1 |  |  |  |  |

| `statement3` | function | statement3/1 |  |  |  |  |

| `subjects_of_type` | function | subjects_of_type/2 |  |  |  |  |

| `supported_gitvan_predicate` | function | supported_gitvan_predicate/3 |  |  |  |  |

| `temporal_window_result` | function | temporal_window_result/4 |  |  |  |  |

| `temporal_window_result` | function | temporal_window_result/4 |  |  |  |  |

| `temporal_window_result` | function | temporal_window_result/4 |  |  |  |  |

| `term_string` | function | term_string/1 |  |  |  |  |

| `term_value` | function | term_value/1 |  |  |  |  |

| `threshold_value` | function | threshold_value/3 |  |  |  |  |

| `threshold_value` | function | threshold_value/3 |  |  |  |  |

| `threshold_value` | function | threshold_value/3 |  |  |  |  |

| `threshold_value_error` | function | threshold_value_error/2 |  |  |  |  |

| `unique_ids` | function | unique_ids/1 |  |  |  |  |

| `verify_bound` | function | verify_bound/4 |  |  |  |  |

| `verify_bound` | function | verify_bound/4 |  |  |  |  |

| `verify_bound` | function | verify_bound/4 |  |  |  |  |

| `verify_query_form` | function | verify_query_form/3 |  |  |  |  |

| `verify_query_form` | function | verify_query_form/3 |  |  |  |  |

| `verify_query_form` | function | verify_query_form/3 |  |  |  |  |

| `verify_query_form` | function | verify_query_form/3 |  |  |  |  |

| `verify_temporal_comparator` | function | verify_temporal_comparator/2 |  |  |  |  |

| `verify_temporal_unit` | function | verify_temporal_unit/2 |  |  |  |  |

| `verify_temporal_unit` | function | verify_temporal_unit/2 |  |  |  |  |

| `verify_time_field` | function | verify_time_field/2 |  |  |  |  |

| `verify_time_field` | function | verify_time_field/2 |  |  |  |  |

| `verify_time_field` | function | verify_time_field/2 |  |  |  |  |

| `verify_window` | function | verify_window/2 |  |  |  |  |

| `verify_window` | function | verify_window/2 |  |  |  |  |


### AshR2RML.KnowledgeHooks.Domain


### AshR2RML.KnowledgeHooks.RaisingHook

| `observe` | function | observe/1 |  |  |  |  |


### AshR2RML.KnowledgeHooks.RaisingWidget

| `AshR2RML.KnowledgeHooks.RaisingWidget` | ash_resource |  |  |  |  |  |


### AshR2RML.KnowledgeHooks.Recorder

| `clear` | function | clear/0 |  |  |  |  |

| `observations` | function | observations/1 |  |  |  |  |

| `record` | function | record/1 |  |  |  |  |

| `start` | function | start/0 |  |  |  |  |


### AshR2RML.KnowledgeHooks.RecordingHook

| `observe` | function | observe/1 |  |  |  |  |


### AshR2RML.KnowledgeHooks.Widget

| `AshR2RML.KnowledgeHooks.Widget` | ash_resource |  |  |  |  |  |


### AshR2RML.LegacyMapping


### AshR2RML.LivebookSpec

| `evaluate_cells` | function | evaluate_cells/2 |  |  |  |  |

| `extract_cells` | function | extract_cells/1 |  |  |  |  |

| `run` | function | run/1 |  |  |  |  |


### AshR2RML.Manufacturing

| `plan` | function | plan/2 |  |  |  |  |

| `verify_staged` | function | verify_staged/2 |  |  |  |  |


### AshR2RML.Manufacturing.Plan


### AshR2RML.Manufacturing.VerificationReceipt


### AshR2RML.Mapping

| `mapping_identity` | function | mapping_identity/1 |  |  |  |  |

| `normalize` | function | normalize/1 |  |  |  |  |

| `normalize` | function | normalize/1 |  |  |  |  |

| `normalize_object_map` | function | normalize_object_map/1 |  |  |  |  |

| `normalize_predicate_object_map` | function | normalize_predicate_object_map/1 |  |  |  |  |

| `normalize_reference_object_map` | function | normalize_reference_object_map/1 |  |  |  |  |

| `normalize_subject_map` | function | normalize_subject_map/1 |  |  |  |  |

| `sort_graph_maps` | function | sort_graph_maps/1 |  |  |  |  |

| `stable_subject_identity?` | function | stable_subject_identity?/1 |  |  |  |  |

| `stable_subject_identity?` | function | stable_subject_identity?/1 |  |  |  |  |

| `stable_subject_identity?` | function | stable_subject_identity?/1 |  |  |  |  |

| `subject_identity_columns` | function | subject_identity_columns/1 |  |  |  |  |

| `subject_identity_columns` | function | subject_identity_columns/1 |  |  |  |  |

| `subject_identity_columns` | function | subject_identity_columns/1 |  |  |  |  |

| `template_fields` | function | template_fields/1 |  |  |  |  |

| `template_fields` | function | template_fields/1 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |

| `validate_classes` | function | validate_classes/1 |  |  |  |  |

| `validate_logical_table` | function | validate_logical_table/1 |  |  |  |  |

| `validate_logical_table` | function | validate_logical_table/1 |  |  |  |  |

| `validate_properties` | function | validate_properties/1 |  |  |  |  |

| `validate_subject` | function | validate_subject/1 |  |  |  |  |

| `validate_subject` | function | validate_subject/1 |  |  |  |  |

| `validate_subject_columns` | function | validate_subject_columns/2 |  |  |  |  |

| `validate_subject_columns` | function | validate_subject_columns/2 |  |  |  |  |

| `validate_subject_columns` | function | validate_subject_columns/2 |  |  |  |  |


### AshR2RML.Mapping.Bundle


### AshR2RML.Mapping.Changeset

| `action_fields` | function | action_fields/0 |  |  |  |  |

| `diff` | function | diff/2 |  |  |  |  |

| `empty?` | function | empty?/1 |  |  |  |  |

| `fetch_graph` | function | fetch_graph/2 |  |  |  |  |

| `get` | function | get/2 |  |  |  |  |

| `get` | function | get/2 |  |  |  |  |

| `inserts` | function | inserts/1 |  |  |  |  |

| `invert` | function | invert/1 |  |  |  |  |

| `merged_graph` | function | merged_graph/1 |  |  |  |  |

| `new` | function | new/1 |  |  |  |  |

| `removals` | function | removals/1 |  |  |  |  |

| `removals` | function | removals/1 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |

| `validate_no_add_remove_overlap` | function | validate_no_add_remove_overlap/1 |  |  |  |  |

| `validate_no_add_remove_overlap` | function | validate_no_add_remove_overlap/1 |  |  |  |  |

| `validate_no_add_remove_overlap` | function | validate_no_add_remove_overlap/1 |  |  |  |  |

| `validate_no_update_replace_overlap` | function | validate_no_update_replace_overlap/1 |  |  |  |  |

| `validate_no_update_replace_overlap` | function | validate_no_update_replace_overlap/1 |  |  |  |  |

| `validate_no_update_replace_overlap` | function | validate_no_update_replace_overlap/1 |  |  |  |  |


### AshR2RML.Mapping.Datatype


### AshR2RML.Mapping.GraphMap


### AshR2RML.Mapping.JoinCondition


### AshR2RML.Mapping.LogicalTable


### AshR2RML.Mapping.ObjectMap


### AshR2RML.Mapping.PredicateObjectMap


### AshR2RML.Mapping.Provenance

| `ash_fields` | function | ash_fields/1 |  |  |  |  |

| `ash_fields` | function | ash_fields/1 |  |  |  |  |

| `attach_generated_at_time` | function | attach_generated_at_time/2 |  |  |  |  |

| `attach_generated_at_time` | function | attach_generated_at_time/3 |  |  |  |  |

| `attach_was_derived_from` | function | attach_was_derived_from/2 |  |  |  |  |

| `available_fields` | function | available_fields/1 |  |  |  |  |

| `get` | function | get/2 |  |  |  |  |

| `get` | function | get/2 |  |  |  |  |

| `pom_matches_field?` | function | pom_matches_field?/2 |  |  |  |  |

| `project` | function | project/2 |  |  |  |  |

| `project` | function | project/2 |  |  |  |  |

| `project` | function | project/2 |  |  |  |  |

| `put_predicate` | function | put_predicate/2 |  |  |  |  |

| `source_datatype` | function | source_datatype/2 |  |  |  |  |

| `source_datatype_from_ash` | function | source_datatype_from_ash/2 |  |  |  |  |

| `source_datatype_from_ash` | function | source_datatype_from_ash/2 |  |  |  |  |

| `validate_generated_at` | function | validate_generated_at/2 |  |  |  |  |

| `validate_generated_at` | function | validate_generated_at/2 |  |  |  |  |

| `validate_generated_at` | function | validate_generated_at/2 |  |  |  |  |

| `validate_template` | function | validate_template/2 |  |  |  |  |

| `validate_template` | function | validate_template/2 |  |  |  |  |

| `validate_template` | function | validate_template/2 |  |  |  |  |


### AshR2RML.Mapping.ReferenceObjectMap


### AshR2RML.Mapping.Resource


### AshR2RML.Mapping.SubjectMap


### AshR2RML.Measurement.ReceiptValidator

| `parse_excluded_tags` | function | parse_excluded_tags/1 |  |  |  |  |

| `parse_exit_status` | function | parse_exit_status/1 |  |  |  |  |

| `parse_test_summary` | function | parse_test_summary/1 |  |  |  |  |

| `parse_timestamp` | function | parse_timestamp/1 |  |  |  |  |

| `reconcile_exclusion_claim` | function | reconcile_exclusion_claim/2 |  |  |  |  |

| `validate` | function | validate/2 |  |  |  |  |

| `validate_freshness` | function | validate_freshness/2 |  |  |  |  |

| `validate_freshness` | function | validate_freshness/2 |  |  |  |  |


### AshR2RML.Mix.SemanticTypes

| `format_refusals` | function | format_refusals/1 |  |  |  |  |

| `json_key` | function | json_key/1 |  |  |  |  |

| `json_key` | function | json_key/1 |  |  |  |  |

| `json_key` | function | json_key/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `load_json` | function | load_json/1 |  |  |  |  |

| `load_source` | function | load_source/1 |  |  |  |  |

| `load_source` | function | load_source/1 |  |  |  |  |

| `plan!` | function | plan!/1 |  |  |  |  |

| `print_json` | function | print_json/1 |  |  |  |  |


### AshR2RML.OBDA.Adapter

| `dispatch` | function | dispatch/3 |  |  |  |  |


### AshR2RML.OBDA.Adapter.InMemoryConfig

| `engine_name` | function | engine_name/0 |  |  |  |  |

| `query` | function | query/3 |  |  |  |  |

| `query` | function | query/3 |  |  |  |  |


### AshR2RML.OBDA.Adapter.OntopConfig

| `engine_name` | function | engine_name/0 |  |  |  |  |

| `query` | function | query/3 |  |  |  |  |


### AshR2RML.OBDA.Capabilities

| `admit` | function | admit/3 |  |  |  |  |

| `mark_executed` | function | mark_executed/1 |  |  |  |  |

| `ontop_supported` | function | ontop_supported/1 |  |  |  |  |

| `query_supported` | function | query_supported/1 |  |  |  |  |

| `query_supported` | function | query_supported/1 |  |  |  |  |

| `seal` | function | seal/1 |  |  |  |  |

| `seal` | function | seal/1 |  |  |  |  |

| `supported` | function | supported/2 |  |  |  |  |

| `supported` | function | supported/2 |  |  |  |  |

| `supported` | function | supported/2 |  |  |  |  |


### AshR2RML.OBDA.CapabilityReceipt


### AshR2RML.OBDA.InMemory

| `materialize` | function | materialize/3 |  |  |  |  |

| `materialize_many` | function | materialize_many/2 |  |  |  |  |


### AshR2RML.OBDA.Observation


### AshR2RML.OBDA.Ontop

| `append_option` | function | append_option/3 |  |  |  |  |

| `append_option` | function | append_option/3 |  |  |  |  |

| `append_option` | function | append_option/3 |  |  |  |  |

| `bounded_failure` | function | bounded_failure/0 |  |  |  |  |

| `bounded_integer` | function | bounded_integer/2 |  |  |  |  |

| `bounded_integer` | function | bounded_integer/2 |  |  |  |  |

| `command` | function | command/1 |  |  |  |  |

| `csv_field` | function | csv_field/1 |  |  |  |  |

| `elapsed` | function | elapsed/1 |  |  |  |  |

| `execute` | function | execute/3 |  |  |  |  |

| `execution_failure` | function | execution_failure/0 |  |  |  |  |

| `finish_csv` | function | finish_csv/3 |  |  |  |  |

| `finish_csv` | function | finish_csv/3 |  |  |  |  |

| `get` | function | get/3 |  |  |  |  |

| `get` | function | get/3 |  |  |  |  |

| `get` | function | get/3 |  |  |  |  |

| `hash_file_or_value` | function | hash_file_or_value/2 |  |  |  |  |

| `hash_file_or_value` | function | hash_file_or_value/2 |  |  |  |  |

| `hash_file_or_value` | function | hash_file_or_value/2 |  |  |  |  |

| `observation_hash` | function | observation_hash/1 |  |  |  |  |

| `parse_csv` | function | parse_csv/1 |  |  |  |  |

| `parse_csv_chars` | function | parse_csv_chars/5 |  |  |  |  |

| `parse_csv_chars` | function | parse_csv_chars/5 |  |  |  |  |

| `parse_csv_chars` | function | parse_csv_chars/5 |  |  |  |  |

| `parse_csv_chars` | function | parse_csv_chars/5 |  |  |  |  |

| `parse_csv_chars` | function | parse_csv_chars/5 |  |  |  |  |

| `parse_csv_chars` | function | parse_csv_chars/5 |  |  |  |  |

| `parse_csv_chars` | function | parse_csv_chars/5 |  |  |  |  |

| `parse_csv_chars` | function | parse_csv_chars/5 |  |  |  |  |

| `query` | function | query/1 |  |  |  |  |

| `query` | function | query/2 |  |  |  |  |

| `redact` | function | redact/1 |  |  |  |  |

| `redact` | function | redact/2 |  |  |  |  |

| `redact` | function | redact/2 |  |  |  |  |

| `redact` | function | redact/2 |  |  |  |  |

| `required` | function | required/2 |  |  |  |  |

| `retained_output` | function | retained_output/2 |  |  |  |  |

| `run_bounded` | function | run_bounded/4 |  |  |  |  |

| `runner_failure` | function | runner_failure/0 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `strip_ontop_log_noise` | function | strip_ontop_log_noise/1 |  |  |  |  |


### AshR2RML.OBDA.Ontop.Compliance

| `counts` | function | counts/1 |  |  |  |  |

| `counts` | function | counts/1 |  |  |  |  |

| `feature_status` | function | feature_status/2 |  |  |  |  |

| `feature_status` | function | feature_status/2 |  |  |  |  |

| `feature_status` | function | feature_status/2 |  |  |  |  |

| `feature_status` | function | feature_status/2 |  |  |  |  |

| `feature_status` | function | feature_status/2 |  |  |  |  |

| `feature_status` | function | feature_status/2 |  |  |  |  |

| `feature_status` | function | feature_status/2 |  |  |  |  |

| `member_status` | function | member_status/2 |  |  |  |  |

| `probe` | function | probe/3 |  |  |  |  |

| `profile` | function | profile/0 |  |  |  |  |

| `protocol_probes` | function | protocol_probes/0 |  |  |  |  |

| `refusal_code` | function | refusal_code/1 |  |  |  |  |

| `refusal_code` | function | refusal_code/1 |  |  |  |  |

| `require_supported` | function | require_supported/2 |  |  |  |  |

| `section_counts` | function | section_counts/1 |  |  |  |  |

| `section_feature_status` | function | section_feature_status/2 |  |  |  |  |

| `sections` | function | sections/1 |  |  |  |  |

| `source_identity` | function | source_identity/0 |  |  |  |  |

| `standard` | function | standard/1 |  |  |  |  |

| `unknown_standard` | function | unknown_standard/1 |  |  |  |  |

| `unprobed` | function | unprobed/1 |  |  |  |  |

| `unprobed_supported_sections` | function | unprobed_supported_sections/1 |  |  |  |  |

| `unprobed_supported_sections` | function | unprobed_supported_sections/1 |  |  |  |  |

| `version` | function | version/0 |  |  |  |  |


### AshR2RML.POWL.Ash.DecomposedNode

| `AshR2RML.POWL.Ash.DecomposedNode` | ash_resource |  |  |  |  |  |


### AshR2RML.POWL.Ash.Domain


### AshR2RML.POWL.Ash.FlowArc

| `AshR2RML.POWL.Ash.FlowArc` | ash_resource |  |  |  |  |  |


### AshR2RML.POWL.Ash.Place

| `AshR2RML.POWL.Ash.Place` | ash_resource |  |  |  |  |  |


### AshR2RML.POWL.Ash.ProcessModel

| `AshR2RML.POWL.Ash.ProcessModel` | ash_resource |  |  |  |  |  |


### AshR2RML.POWL.Ash.Transition

| `AshR2RML.POWL.Ash.Transition` | ash_resource |  |  |  |  |  |


### AshR2RML.POWL.AshPowlPipeline


### AshR2RML.POWL.DBSeeder

| `seed_retailer_process!` | function | seed_retailer_process!/0 |  |  |  |  |


### AshR2RML.POWL.DecomposerReactor


### AshR2RML.POWL.Model


### AshR2RML.POWL.WorkflowNet

| `new` | function | new/6 |  |  |  |  |


### AshR2RML.PalantirMigrationFixture.Asset

| `AshR2RML.PalantirMigrationFixture.Asset` | ash_resource |  |  |  |  |  |


### AshR2RML.PalantirMigrationFixture.Organization

| `AshR2RML.PalantirMigrationFixture.Organization` | ash_resource |  |  |  |  |  |


### AshR2RML.Parity

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `compare` | function | compare/5 |  |  |  |  |

| `default_left` | function | default_left/1 |  |  |  |  |

| `default_right` | function | default_right/1 |  |  |  |  |

| `get` | function | get/2 |  |  |  |  |

| `normalize_multiset` | function | normalize_multiset/1 |  |  |  |  |

| `present_hash?` | function | present_hash?/1 |  |  |  |  |

| `query_hash` | function | query_hash/1 |  |  |  |  |

| `query_hash` | function | query_hash/1 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |


### AshR2RML.ParityReceipt


### AshR2RML.PersistMapping

| `__ash_r2rml_mapping__` | function | __ash_r2rml_mapping__/0 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `column_for_attribute` | function | column_for_attribute/2 |  |  |  |  |

| `column_for_attribute` | function | column_for_attribute/2 |  |  |  |  |

| `transform` | function | transform/1 |  |  |  |  |


### AshR2RML.Policy

| `filter_for_actor` | function | filter_for_actor/3 |  |  |  |  |

| `filter_for_actor` | function | filter_for_actor/3 |  |  |  |  |


### AshR2RML.Production

| `evidence_identity` | function | evidence_identity/1 |  |  |  |  |

| `fetch` | function | fetch/3 |  |  |  |  |

| `normalize_evidence` | function | normalize_evidence/1 |  |  |  |  |

| `normalize_evidence` | function | normalize_evidence/1 |  |  |  |  |

| `present?` | function | present?/1 |  |  |  |  |

| `refusal` | function | refusal/4 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `standing` | function | standing/1 |  |  |  |  |

| `standing` | function | standing/1 |  |  |  |  |

| `standing` | function | standing/1 |  |  |  |  |

| `valid_evidence?` | function | valid_evidence?/2 |  |  |  |  |


### AshR2RML.Production.Capabilities


### AshR2RML.Production.Deployment


### AshR2RML.Production.Observability

| `contract` | function | contract/2 |  |  |  |  |

| `validate_labels` | function | validate_labels/1 |  |  |  |  |


### AshR2RML.Production.Quota

| `admit` | function | admit/2 |  |  |  |  |


### AshR2RML.Production.Release

| `contract` | function | contract/1 |  |  |  |  |

| `stages` | function | stages/1 |  |  |  |  |

| `stages` | function | stages/1 |  |  |  |  |

| `stages` | function | stages/1 |  |  |  |  |

| `stages` | function | stages/1 |  |  |  |  |


### AshR2RML.Production.Resilience

| `contract` | function | contract/2 |  |  |  |  |


### AshR2RML.Production.Router


### AshR2RML.Production.SLO

| `burn_status` | function | burn_status/1 |  |  |  |  |

| `burn_status` | function | burn_status/1 |  |  |  |  |

| `burn_status` | function | burn_status/1 |  |  |  |  |

| `burn_status` | function | burn_status/1 |  |  |  |  |

| `capacity` | function | capacity/2 |  |  |  |  |

| `ceil_div` | function | ceil_div/2 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `error_budget` | function | error_budget/2 |  |  |  |  |

| `evaluate` | function | evaluate/2 |  |  |  |  |

| `fetch` | function | fetch/3 |  |  |  |  |

| `number` | function | number/3 |  |  |  |  |

| `target_for` | function | target_for/2 |  |  |  |  |

| `target_for` | function | target_for/2 |  |  |  |  |


### AshR2RML.Production.Security

| `contract` | function | contract/1 |  |  |  |  |


### AshR2RML.Production.Workload

| `fetch` | function | fetch/3 |  |  |  |  |

| `new` | function | new/1 |  |  |  |  |

| `present?` | function | present?/1 |  |  |  |  |

| `refusal` | function | refusal/2 |  |  |  |  |


### AshR2RML.Proof

| `achieved?` | function | achieved?/2 |  |  |  |  |

| `add` | function | add/2 |  |  |  |  |

| `add` | function | add/2 |  |  |  |  |

| `classes` | function | classes/0 |  |  |  |  |

| `highest` | function | highest/1 |  |  |  |  |


### AshR2RML.R2RML

| `render` | function | render/1 |  |  |  |  |

| `render` | function | render/1 |  |  |  |  |

| `render` | function | render/1 |  |  |  |  |

| `render_bundle` | function | render_bundle/1 |  |  |  |  |


### AshR2RML.RDF.GraphAlgebra

| `equivalent?` | function | equivalent?/2 |  |  |  |  |

| `graph_add` | function | graph_add/2 |  |  |  |  |

| `graph_add` | function | graph_add/2 |  |  |  |  |

| `graph_cleanup` | function | graph_cleanup/1 |  |  |  |  |

| `graph_delete` | function | graph_delete/2 |  |  |  |  |

| `graph_delete` | function | graph_delete/2 |  |  |  |  |

| `graph_intersection` | function | graph_intersection/2 |  |  |  |  |


### AshR2RML.Reactor.CompileR2RML

| `run` | function | run/3 |  |  |  |  |


### AshR2RML.Reactor.CompileR2RML

| `run` | function | run/3 |  |  |  |  |


### AshR2RML.Reactor.Middleware.TelemetryLogger

| `complete` | function | complete/2 |  |  |  |  |

| `elapsed` | function | elapsed/2 |  |  |  |  |

| `error` | function | error/2 |  |  |  |  |

| `event` | function | event/3 |  |  |  |  |

| `event` | function | event/3 |  |  |  |  |

| `event` | function | event/3 |  |  |  |  |

| `evidence_result` | function | evidence_result/1 |  |  |  |  |

| `evidence_result` | function | evidence_result/1 |  |  |  |  |

| `init` | function | init/1 |  |  |  |  |


### AshR2RML.Reactor.Pipeline


### AshR2RML.Reactor.Steps.ApplyPolicy

| `run` | function | run/3 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |


### AshR2RML.Reactor.Steps.AttachProvenance

| `lookup_override` | function | lookup_override/2 |  |  |  |  |

| `provenance_from_metadata` | function | provenance_from_metadata/1 |  |  |  |  |

| `provenance_from_metadata` | function | provenance_from_metadata/1 |  |  |  |  |

| `resource_config` | function | resource_config/2 |  |  |  |  |

| `resource_config` | function | resource_config/2 |  |  |  |  |

| `resource_config` | function | resource_config/2 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |


### AshR2RML.Reactor.Steps.CompileResources

| `compensate` | function | compensate/4 |  |  |  |  |

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |


### AshR2RML.Reactor.Steps.EvaluateDifferential

| `run` | function | run/3 |  |  |  |  |


### AshR2RML.Reactor.Steps.RenderTurtle

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |


### AshR2RML.Reactor.Steps.VerifyAlignment

| `run` | function | run/3 |  |  |  |  |


### AshR2RML.Refusal

| `new` | function | new/4 |  |  |  |  |


### AshR2RML.RelationshipMapping


### AshR2RML.Resource

| `convert_legacy` | function | convert_legacy/2 |  |  |  |  |

| `safe_spark_opt` | function | safe_spark_opt/3 |  |  |  |  |

| `section` | function | section/0 |  |  |  |  |

| `spark_resource?` | function | spark_resource?/1 |  |  |  |  |


### AshR2RML.Resource.Info

| `mapped?` | function | mapped?/1 |  |  |  |  |

| `mapping` | function | mapping/1 |  |  |  |  |

| `mapping!` | function | mapping!/1 |  |  |  |  |

| `mapping_result` | function | mapping_result/1 |  |  |  |  |

| `sparql_queries` | function | sparql_queries/1 |  |  |  |  |


### AshR2RML.Resource.LegacyAdapter

| `convert` | function | convert/1 |  |  |  |  |


### AshR2RML.Resource.Persist

| `after?` | function | after?/1 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `compile_dsl_relationship` | function | compile_dsl_relationship/3 |  |  |  |  |

| `compile_graphs` | function | compile_graphs/2 |  |  |  |  |

| `compile_object_map` | function | compile_object_map/3 |  |  |  |  |

| `compile_properties` | function | compile_properties/3 |  |  |  |  |

| `compile_property` | function | compile_property/3 |  |  |  |  |

| `compile_references` | function | compile_references/3 |  |  |  |  |

| `compile_subject` | function | compile_subject/3 |  |  |  |  |

| `compile_subject` | function | compile_subject/3 |  |  |  |  |

| `find_dsl_attribute` | function | find_dsl_attribute/2 |  |  |  |  |

| `reverse_ok` | function | reverse_ok/1 |  |  |  |  |

| `reverse_ok` | function | reverse_ok/1 |  |  |  |  |

| `transform` | function | transform/1 |  |  |  |  |


### AshR2RML.Resource.Verify

| `verify` | function | verify/1 |  |  |  |  |


### AshR2RML.SHACL

| `render` | function | render/1 |  |  |  |  |

| `render` | function | render/1 |  |  |  |  |


### AshR2RML.SPARQL

| `build_plan` | function | build_plan/3 |  |  |  |  |

| `build_plan` | function | build_plan/3 |  |  |  |  |

| `execute` | function | execute/1 |  |  |  |  |

| `execute` | function | execute/1 |  |  |  |  |

| `execute` | function | execute/1 |  |  |  |  |

| `execute` | function | execute/1 |  |  |  |  |

| `execute` | function | execute/1 |  |  |  |  |

| `explore` | function | explore/2 |  |  |  |  |

| `maybe_candidate` | function | maybe_candidate/3 |  |  |  |  |

| `maybe_candidate` | function | maybe_candidate/3 |  |  |  |  |


### AshR2RML.SPARQL.Differential

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `common_query_identity` | function | common_query_identity/1 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `require_observations` | function | require_observations/1 |  |  |  |  |

| `require_observations` | function | require_observations/1 |  |  |  |  |

| `require_observed` | function | require_observed/1 |  |  |  |  |

| `require_strategies` | function | require_strategies/2 |  |  |  |  |

| `unique_strategies` | function | unique_strategies/1 |  |  |  |  |


### AshR2RML.SPARQL.DifferentialReceipt


### AshR2RML.SPARQL.Local

| `normalize_local_result` | function | normalize_local_result/2 |  |  |  |  |

| `normalize_local_result` | function | normalize_local_result/2 |  |  |  |  |

| `query` | function | query/2 |  |  |  |  |


### AshR2RML.SPARQL.Observation


### AshR2RML.SPARQL.Plan


### AshR2RML.SPARQL.Protocol

| `do_query` | function | do_query/6 |  |  |  |  |

| `query` | function | query/3 |  |  |  |  |

| `query_with` | function | query_with/4 |  |  |  |  |


### AshR2RML.SPARQL.Query

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/2 |  |  |  |  |

| `load_file` | function | load_file/2 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |


### AshR2RML.SPARQL.Result

| `hash_rows` | function | hash_rows/1 |  |  |  |  |

| `normalize` | function | normalize/1 |  |  |  |  |

| `normalize` | function | normalize/1 |  |  |  |  |

| `normalize` | function | normalize/1 |  |  |  |  |

| `normalize_binding` | function | normalize_binding/1 |  |  |  |  |

| `normalize_rdf_value` | function | normalize_rdf_value/1 |  |  |  |  |

| `normalize_statement` | function | normalize_statement/1 |  |  |  |  |

| `normalize_statement` | function | normalize_statement/1 |  |  |  |  |

| `normalize_term` | function | normalize_term/1 |  |  |  |  |

| `normalize_term` | function | normalize_term/1 |  |  |  |  |

| `normalize_term` | function | normalize_term/1 |  |  |  |  |

| `normalize_var_name` | function | normalize_var_name/1 |  |  |  |  |

| `normalize_var_name` | function | normalize_var_name/1 |  |  |  |  |

| `normalize_var_name` | function | normalize_var_name/1 |  |  |  |  |

| `normalize_var_name` | function | normalize_var_name/1 |  |  |  |  |


### AshR2RML.Security

| `field_policy_protected?` | function | field_policy_protected?/2 |  |  |  |  |

| `non_attribute_mapped_fields` | function | non_attribute_mapped_fields/2 |  |  |  |  |

| `remove_attributes` | function | remove_attributes/2 |  |  |  |  |

| `remove_attributes` | function | remove_attributes/3 |  |  |  |  |

| `remove_attributes` | function | remove_attributes/3 |  |  |  |  |

| `sanitize_in_memory_mapping` | function | sanitize_in_memory_mapping/2 |  |  |  |  |

| `sanitize_mapping` | function | sanitize_mapping/2 |  |  |  |  |

| `unenforceable_attributes` | function | unenforceable_attributes/2 |  |  |  |  |


### AshR2RML.Semantic.Ash

| `render` | function | render/2 |  |  |  |  |

| `render` | function | render/2 |  |  |  |  |


### AshR2RML.Semantic.Ecto

| `render` | function | render/1 |  |  |  |  |

| `render_foreign_keys` | function | render_foreign_keys/2 |  |  |  |  |

| `render_table` | function | render_table/1 |  |  |  |  |

| `verify_types` | function | verify_types/1 |  |  |  |  |


### AshR2RML.Semantic.GraphQL

| `attribute_field` | function | attribute_field/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `describe_resource` | function | describe_resource/3 |  |  |  |  |

| `manifest_resource` | function | manifest_resource/1 |  |  |  |  |

| `relationship_field` | function | relationship_field/3 |  |  |  |  |

| `render_query` | function | render_query/1 |  |  |  |  |

| `render_query` | function | render_query/1 |  |  |  |  |

| `render_schema` | function | render_schema/1 |  |  |  |  |

| `render_type` | function | render_type/1 |  |  |  |  |

| `semantic_field_name` | function | semantic_field_name/2 |  |  |  |  |


### AshR2RML.Semantic.R2RML

| `literal` | function | literal/1 |  |  |  |  |

| `map_id` | function | map_id/1 |  |  |  |  |

| `module_parts` | function | module_parts/1 |  |  |  |  |

| `module_parts` | function | module_parts/1 |  |  |  |  |

| `predicate_suffix` | function | predicate_suffix/1 |  |  |  |  |

| `predicate_suffix` | function | predicate_suffix/1 |  |  |  |  |

| `remap_template` | function | remap_template/3 |  |  |  |  |

| `render` | function | render/1 |  |  |  |  |

| `render_attribute` | function | render_attribute/1 |  |  |  |  |

| `render_fk_relationship` | function | render_fk_relationship/3 |  |  |  |  |

| `render_join_maps` | function | render_join_maps/2 |  |  |  |  |

| `render_resource` | function | render_resource/2 |  |  |  |  |


### AshR2RML.Semantic.SHACL

| `attribute_shape` | function | attribute_shape/1 |  |  |  |  |

| `max_count` | function | max_count/1 |  |  |  |  |

| `max_count` | function | max_count/1 |  |  |  |  |

| `relationship_shape` | function | relationship_shape/2 |  |  |  |  |

| `render` | function | render/1 |  |  |  |  |

| `render_resource` | function | render_resource/2 |  |  |  |  |


### AshR2RML.Semantic.SQL

| `attribute_column!` | function | attribute_column!/2 |  |  |  |  |

| `column_definition` | function | column_definition/1 |  |  |  |  |

| `identity_constraints` | function | identity_constraints/1 |  |  |  |  |

| `quote_ident` | function | quote_ident/1 |  |  |  |  |

| `render` | function | render/1 |  |  |  |  |

| `render_foreign_keys` | function | render_foreign_keys/2 |  |  |  |  |

| `render_join_tables` | function | render_join_tables/2 |  |  |  |  |

| `render_table` | function | render_table/1 |  |  |  |  |


### AshR2RML.SemanticAdapter

| `convert_resource` | function | convert_resource/2 |  |  |  |  |

| `to_mapping` | function | to_mapping/1 |  |  |  |  |


### AshR2RML.SemanticDrift

| `compare` | function | compare/2 |  |  |  |  |

| `compare_resources` | function | compare_resources/2 |  |  |  |  |

| `index_resources` | function | index_resources/1 |  |  |  |  |


### AshR2RML.SemanticIR


### AshR2RML.SemanticIR.Action


### AshR2RML.SemanticIR.Attribute


### AshR2RML.SemanticIR.Identity


### AshR2RML.SemanticIR.Policy


### AshR2RML.SemanticIR.Relationship


### AshR2RML.SemanticIR.Resource


### AshR2RML.SemanticSessionIdentity

| `admit_reuse` | function | admit_reuse/2 |  |  |  |  |

| `app_version` | function | app_version/0 |  |  |  |  |

| `bind_environment` | function | bind_environment/2 |  |  |  |  |

| `get` | function | get/3 |  |  |  |  |

| `identity_hash` | function | identity_hash/1 |  |  |  |  |

| `matches?` | function | matches?/2 |  |  |  |  |

| `module_sha256` | function | module_sha256/1 |  |  |  |  |

| `new` | function | new/1 |  |  |  |  |


### AshR2RML.SemanticSubject

| `field` | function | field/2 |  |  |  |  |

| `from_ir` | function | from_ir/1 |  |  |  |  |

| `manufacture_input` | function | manufacture_input/1 |  |  |  |  |

| `present` | function | present/2 |  |  |  |  |

| `present` | function | present/2 |  |  |  |  |

| `resolved_material` | function | resolved_material/1 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `strip_sha256` | function | strip_sha256/1 |  |  |  |  |


### AshR2RML.SemanticType

| `absolute_iri?` | function | absolute_iri?/1 |  |  |  |  |

| `absolute_iri?` | function | absolute_iri?/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `get` | function | get/3 |  |  |  |  |

| `hash` | function | hash/1 |  |  |  |  |

| `new` | function | new/1 |  |  |  |  |

| `new` | function | new/1 |  |  |  |  |

| `refusal` | function | refusal/4 |  |  |  |  |


### AshR2RML.SemanticType.DfCM

| `candidates` | function | candidates/1 |  |  |  |  |

| `candidates` | function | candidates/1 |  |  |  |  |

| `candidates` | function | candidates/1 |  |  |  |  |

| `candidates` | function | candidates/1 |  |  |  |  |

| `candidates` | function | candidates/1 |  |  |  |  |

| `candidates` | function | candidates/1 |  |  |  |  |

| `select` | function | select/1 |  |  |  |  |


### AshR2RML.SemanticType.Diff


### AshR2RML.SemanticType.Plan


### AshR2RML.SemanticType.Provider


### AshR2RML.SemanticTypes

| `admit_property` | function | admit_property/2 |  |  |  |  |

| `apply_entry_overrides` | function | apply_entry_overrides/2 |  |  |  |  |

| `apply_overrides` | function | apply_overrides/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile_entry` | function | compile_entry/2 |  |  |  |  |

| `compile_entry` | function | compile_entry/2 |  |  |  |  |

| `compile_entry` | function | compile_entry/2 |  |  |  |  |

| `diff` | function | diff/2 |  |  |  |  |

| `encode_rdf` | function | encode_rdf/2 |  |  |  |  |

| `entry?` | function | entry?/1 |  |  |  |  |

| `existing_atom` | function | existing_atom/1 |  |  |  |  |

| `existing_atom` | function | existing_atom/1 |  |  |  |  |

| `existing_atom` | function | existing_atom/1 |  |  |  |  |

| `get` | function | get/3 |  |  |  |  |

| `index_manifest_types` | function | index_manifest_types/1 |  |  |  |  |

| `iri_type` | function | iri_type/1 |  |  |  |  |

| `manifest` | function | manifest/1 |  |  |  |  |

| `manifest_json` | function | manifest_json/1 |  |  |  |  |

| `manifest_type` | function | manifest_type/1 |  |  |  |  |

| `maybe_refuse` | function | maybe_refuse/5 |  |  |  |  |

| `maybe_refuse` | function | maybe_refuse/5 |  |  |  |  |

| `normalize_compare` | function | normalize_compare/1 |  |  |  |  |

| `normalize_compare` | function | normalize_compare/1 |  |  |  |  |

| `normalize_compare` | function | normalize_compare/1 |  |  |  |  |

| `normalize_compare` | function | normalize_compare/1 |  |  |  |  |

| `normalize_manifest` | function | normalize_manifest/1 |  |  |  |  |

| `normalize_manifest` | function | normalize_manifest/1 |  |  |  |  |

| `normalize_result` | function | normalize_result/1 |  |  |  |  |

| `normalize_result` | function | normalize_result/1 |  |  |  |  |

| `normalize_result` | function | normalize_result/1 |  |  |  |  |

| `plan` | function | plan/2 |  |  |  |  |

| `plan_hash` | function | plan_hash/2 |  |  |  |  |

| `providers` | function | providers/1 |  |  |  |  |

| `representation` | function | representation/1 |  |  |  |  |

| `representation` | function | representation/1 |  |  |  |  |

| `representation` | function | representation/1 |  |  |  |  |

| `representation` | function | representation/1 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `round_trip` | function | round_trip/2 |  |  |  |  |

| `semantic_ash_compatible?` | function | semantic_ash_compatible?/2 |  |  |  |  |

| `semantic_ash_compatible?` | function | semantic_ash_compatible?/2 |  |  |  |  |

| `semantic_ash_compatible?` | function | semantic_ash_compatible?/2 |  |  |  |  |

| `semantic_differences` | function | semantic_differences/2 |  |  |  |  |

| `semantic_round_trip` | function | semantic_round_trip/2 |  |  |  |  |

| `type_identity` | function | type_identity/1 |  |  |  |  |

| `type_key` | function | type_key/1 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |

| `verify_type` | function | verify_type/1 |  |  |  |  |


### AshR2RML.SemanticTypes.Dsl.Type


### AshR2RML.SemanticTypes.Generator

| `files` | function | files/2 |  |  |  |  |

| `igniter_files` | function | igniter_files/3 |  |  |  |  |

| `plan_id` | function | plan_id/0 |  |  |  |  |

| `render_contract_tests` | function | render_contract_tests/2 |  |  |  |  |

| `render_elixir` | function | render_elixir/2 |  |  |  |  |

| `render_new_type` | function | render_new_type/2 |  |  |  |  |

| `semantic_type_ids` | function | semantic_type_ids/0 |  |  |  |  |


### AshR2RML.SemanticTypes.GeoSPARQL

| `catalogue` | function | catalogue/0 |  |  |  |  |

| `id` | function | id/0 |  |  |  |  |

| `prefixes` | function | prefixes/0 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |


### AshR2RML.SemanticTypes.OWLTime

| `catalogue` | function | catalogue/0 |  |  |  |  |

| `id` | function | id/0 |  |  |  |  |

| `prefixes` | function | prefixes/0 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |


### AshR2RML.SemanticTypes.ProviderSupport

| `type` | function | type/6 |  |  |  |  |


### AshR2RML.SemanticTypes.QUDT

| `catalogue` | function | catalogue/0 |  |  |  |  |

| `id` | function | id/0 |  |  |  |  |

| `prefixes` | function | prefixes/0 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |


### AshR2RML.SemanticTypes.RDF

| `catalogue` | function | catalogue/0 |  |  |  |  |

| `id` | function | id/0 |  |  |  |  |

| `prefixes` | function | prefixes/0 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |


### AshR2RML.SemanticTypes.Resource


### AshR2RML.SemanticTypes.Resource.Info

| `plan` | function | plan/1 |  |  |  |  |


### AshR2RML.SemanticTypes.Resource.Persist

| `transform` | function | transform/1 |  |  |  |  |


### AshR2RML.SemanticTypes.SKOS

| `catalogue` | function | catalogue/0 |  |  |  |  |

| `id` | function | id/0 |  |  |  |  |

| `prefixes` | function | prefixes/0 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |


### AshR2RML.SemanticTypes.XSD

| `catalogue` | function | catalogue/0 |  |  |  |  |

| `id` | function | id/0 |  |  |  |  |

| `name` | function | name/1 |  |  |  |  |

| `prefixes` | function | prefixes/0 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |


### AshR2RML.SemanticValue

| `cardinality_change` | function | cardinality_change/5 |  |  |  |  |

| `change` | function | change/4 |  |  |  |  |

| `classify` | function | classify/1 |  |  |  |  |

| `classify` | function | classify/1 |  |  |  |  |

| `compare_attribute` | function | compare_attribute/3 |  |  |  |  |

| `compare_attributes` | function | compare_attributes/3 |  |  |  |  |

| `compare_relationship` | function | compare_relationship/3 |  |  |  |  |

| `compare_relationships` | function | compare_relationships/3 |  |  |  |  |

| `compare_resource` | function | compare_resource/2 |  |  |  |  |

| `kind` | function | kind/1 |  |  |  |  |

| `narrower_max?` | function | narrower_max?/2 |  |  |  |  |

| `narrower_max?` | function | narrower_max?/2 |  |  |  |  |

| `narrower_max?` | function | narrower_max?/2 |  |  |  |  |

| `not_asserted` | function | not_asserted/0 |  |  |  |  |

| `not_projected` | function | not_projected/1 |  |  |  |  |

| `null` | function | null/0 |  |  |  |  |

| `refused` | function | refused/1 |  |  |  |  |

| `unbound` | function | unbound/0 |  |  |  |  |

| `union_keys` | function | union_keys/2 |  |  |  |  |

| `unknown` | function | unknown/1 |  |  |  |  |

| `unsupported` | function | unsupported/1 |  |  |  |  |

| `value` | function | value/1 |  |  |  |  |

| `wider_max?` | function | wider_max?/2 |  |  |  |  |

| `wider_max?` | function | wider_max?/2 |  |  |  |  |

| `wider_max?` | function | wider_max?/2 |  |  |  |  |


### AshR2RML.ShortNameCollision.Domain


### AshR2RML.ShortNameCollision.NsA.Widget

| `AshR2RML.ShortNameCollision.NsA.Widget` | ash_resource |  |  |  |  |  |


### AshR2RML.ShortNameCollision.NsB.Widget

| `AshR2RML.ShortNameCollision.NsB.Widget` | ash_resource |  |  |  |  |  |


### AshR2RML.Telemetry.FlyClient

| `build_envelope` | function | build_envelope/5 |  |  |  |  |

| `canonicalize_map` | function | canonicalize_map/1 |  |  |  |  |

| `canonicalize_val` | function | canonicalize_val/1 |  |  |  |  |

| `canonicalize_val` | function | canonicalize_val/1 |  |  |  |  |

| `compute_digest` | function | compute_digest/4 |  |  |  |  |

| `compute_digest` | function | compute_digest/1 |  |  |  |  |

| `compute_subject_sha` | function | compute_subject_sha/0 |  |  |  |  |

| `default_producer` | function | default_producer/1 |  |  |  |  |

| `dispatch_envelope` | function | dispatch_envelope/2 |  |  |  |  |

| `do_flush` | function | do_flush/1 |  |  |  |  |

| `do_flush` | function | do_flush/1 |  |  |  |  |

| `do_replay_offline` | function | do_replay_offline/2 |  |  |  |  |

| `ensure_inets_started` | function | ensure_inets_started/0 |  |  |  |  |

| `flush` | function | flush/1 |  |  |  |  |

| `generate_run_id` | function | generate_run_id/0 |  |  |  |  |

| `get_control_plane_url` | function | get_control_plane_url/0 |  |  |  |  |

| `get_state` | function | get_state/1 |  |  |  |  |

| `handle_call` | function | handle_call/3 |  |  |  |  |

| `handle_call` | function | handle_call/3 |  |  |  |  |

| `handle_call` | function | handle_call/3 |  |  |  |  |

| `handle_call` | function | handle_call/3 |  |  |  |  |

| `handle_call` | function | handle_call/3 |  |  |  |  |

| `handle_info` | function | handle_info/2 |  |  |  |  |

| `httpc_post` | function | httpc_post/4 |  |  |  |  |

| `init` | function | init/1 |  |  |  |  |

| `normalize_endpoint_url` | function | normalize_endpoint_url/1 |  |  |  |  |

| `normalize_producer` | function | normalize_producer/1 |  |  |  |  |

| `normalize_producer` | function | normalize_producer/1 |  |  |  |  |

| `normalize_producer` | function | normalize_producer/1 |  |  |  |  |

| `push_event` | function | push_event/2 |  |  |  |  |

| `push_events` | function | push_events/2 |  |  |  |  |

| `read_offline_fallback` | function | read_offline_fallback/1 |  |  |  |  |

| `read_offline_fallback` | function | read_offline_fallback/1 |  |  |  |  |

| `replay_offline` | function | replay_offline/2 |  |  |  |  |

| `schedule_flush` | function | schedule_flush/1 |  |  |  |  |

| `sign_digest` | function | sign_digest/2 |  |  |  |  |

| `start_link` | function | start_link/1 |  |  |  |  |

| `stop` | function | stop/1 |  |  |  |  |

| `terminate` | function | terminate/2 |  |  |  |  |

| `verify_chain` | function | verify_chain/1 |  |  |  |  |

| `verify_chain` | function | verify_chain/1 |  |  |  |  |

| `verify_digest` | function | verify_digest/1 |  |  |  |  |

| `verify_digest` | function | verify_digest/1 |  |  |  |  |

| `write_offline_fallback` | function | write_offline_fallback/2 |  |  |  |  |

| `write_offline_fallback` | function | write_offline_fallback/2 |  |  |  |  |


### AshR2RML.Telemetry.OCEL2

| `check_conformance` | function | check_conformance/2 |  |  |  |  |

| `check_conformance` | function | check_conformance/2 |  |  |  |  |

| `check_conformance` | function | check_conformance/2 |  |  |  |  |

| `check_conformance` | function | check_conformance/2 |  |  |  |  |

| `check_conformance` | function | check_conformance/2 |  |  |  |  |

| `validate_event_schema` | function | validate_event_schema/1 |  |  |  |  |


### AshR2RML.Telemetry.OcelAshEmitter

| `append_ocel_event!` | function | append_ocel_event!/2 |  |  |  |  |

| `attach!` | function | attach!/1 |  |  |  |  |

| `build_notification_ocel_event` | function | build_notification_ocel_event/3 |  |  |  |  |

| `build_ocel_event` | function | build_ocel_event/3 |  |  |  |  |

| `build_reactor_pipeline_event` | function | build_reactor_pipeline_event/3 |  |  |  |  |

| `build_reactor_step_ocel_event` | function | build_reactor_step_ocel_event/3 |  |  |  |  |

| `default_log_path` | function | default_log_path/0 |  |  |  |  |

| `detach_all!` | function | detach_all!/1 |  |  |  |  |

| `duration_ms` | function | duration_ms/1 |  |  |  |  |

| `execution_object` | function | execution_object/1 |  |  |  |  |

| `execution_object` | function | execution_object/1 |  |  |  |  |

| `extract_step_facts` | function | extract_step_facts/2 |  |  |  |  |

| `extract_step_facts` | function | extract_step_facts/2 |  |  |  |  |

| `extract_step_facts` | function | extract_step_facts/2 |  |  |  |  |

| `extract_step_facts` | function | extract_step_facts/2 |  |  |  |  |

| `extract_step_facts` | function | extract_step_facts/2 |  |  |  |  |

| `extract_step_facts` | function | extract_step_facts/2 |  |  |  |  |

| `get_r2rml_class` | function | get_r2rml_class/1 |  |  |  |  |

| `handle_event` | function | handle_event/4 |  |  |  |  |

| `handle_notification_event` | function | handle_notification_event/4 |  |  |  |  |

| `handle_reactor_pipeline_event` | function | handle_reactor_pipeline_event/4 |  |  |  |  |

| `handle_reactor_step_event` | function | handle_reactor_step_event/4 |  |  |  |  |

| `safe_step_name` | function | safe_step_name/1 |  |  |  |  |

| `safe_step_name` | function | safe_step_name/1 |  |  |  |  |

| `safe_step_name` | function | safe_step_name/1 |  |  |  |  |

| `safe_step_name` | function | safe_step_name/1 |  |  |  |  |

| `safe_step_name` | function | safe_step_name/1 |  |  |  |  |

| `safe_step_name` | function | safe_step_name/1 |  |  |  |  |

| `with_execution_object` | function | with_execution_object/3 |  |  |  |  |


### AshR2RML.Test.DockerInfraCheck

| `container_running?` | function | container_running?/0 |  |  |  |  |

| `ensure_infra` | function | ensure_infra/0 |  |  |  |  |

| `network_exists?` | function | network_exists?/0 |  |  |  |  |

| `skip_reason` | function | skip_reason/0 |  |  |  |  |


### AshR2RML.Type

| `class_iri` | function | class_iri/0 |  |  |  |  |

| `concept_scheme_iri` | function | concept_scheme_iri/0 |  |  |  |  |

| `contract` | function | contract/1 |  |  |  |  |

| `datatype_iri` | function | datatype_iri/0 |  |  |  |  |

| `decode` | function | decode/2 |  |  |  |  |

| `encode` | function | encode/2 |  |  |  |  |

| `exported` | function | exported/2 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `from_rdf_lexical` | function | from_rdf_lexical/1 |  |  |  |  |

| `semantic_kind` | function | semantic_kind/0 |  |  |  |  |

| `semantic_type?` | function | semantic_type?/1 |  |  |  |  |

| `semantic_type?` | function | semantic_type?/1 |  |  |  |  |

| `shacl_constraints` | function | shacl_constraints/0 |  |  |  |  |

| `to_rdf` | function | to_rdf/1 |  |  |  |  |

| `to_rdf_lexical` | function | to_rdf_lexical/1 |  |  |  |  |

| `xsd_datatype` | function | xsd_datatype/0 |  |  |  |  |


### AshR2RML.Types.Concept

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `constraints` | function | constraints/0 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `equal?` | function | equal?/2 |  |  |  |  |

| `equal?` | function | equal?/2 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `storage_type` | function | storage_type/1 |  |  |  |  |

| `to_rdf` | function | to_rdf/1 |  |  |  |  |

| `to_rdf` | function | to_rdf/1 |  |  |  |  |

| `validate` | function | validate/2 |  |  |  |  |


### AshR2RML.Types.IRI

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `constraints` | function | constraints/0 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `prefix_ok?` | function | prefix_ok?/2 |  |  |  |  |

| `prefix_ok?` | function | prefix_ok?/2 |  |  |  |  |

| `storage_type` | function | storage_type/1 |  |  |  |  |

| `to_rdf` | function | to_rdf/1 |  |  |  |  |

| `to_rdf` | function | to_rdf/1 |  |  |  |  |

| `validate` | function | validate/2 |  |  |  |  |


### AshR2RML.Types.LangString

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `storage_type` | function | storage_type/1 |  |  |  |  |

| `to_rdf` | function | to_rdf/1 |  |  |  |  |

| `to_rdf` | function | to_rdf/1 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |


### AshR2RML.Types.Quantity

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `constraints` | function | constraints/0 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `numeric?` | function | numeric?/1 |  |  |  |  |

| `storage_type` | function | storage_type/1 |  |  |  |  |

| `to_rdf` | function | to_rdf/1 |  |  |  |  |

| `to_rdf` | function | to_rdf/1 |  |  |  |  |

| `validate` | function | validate/2 |  |  |  |  |


### AshR2RML.Types.TemporalInterval

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `storage_type` | function | storage_type/1 |  |  |  |  |

| `to_rdf` | function | to_rdf/1 |  |  |  |  |

| `to_rdf` | function | to_rdf/1 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |


### AshR2RML.VKG

| `catalog` | function | catalog/1 |  |  |  |  |

| `catalog` | function | catalog/1 |  |  |  |  |

| `catalog` | function | catalog/1 |  |  |  |  |

| `check_expected` | function | check_expected/2 |  |  |  |  |

| `check_expected` | function | check_expected/2 |  |  |  |  |

| `check_expected` | function | check_expected/2 |  |  |  |  |

| `do_verify` | function | do_verify/2 |  |  |  |  |

| `expected_catalog` | function | expected_catalog/1 |  |  |  |  |

| `opts_refusal` | function | opts_refusal/1 |  |  |  |  |

| `query` | function | query/2 |  |  |  |  |

| `query` | function | query/2 |  |  |  |  |

| `query` | function | query/2 |  |  |  |  |

| `query` | function | query/2 |  |  |  |  |

| `query_all` | function | query_all/1 |  |  |  |  |

| `query_all` | function | query_all/1 |  |  |  |  |

| `query_all` | function | query_all/1 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `verify` | function | verify/2 |  |  |  |  |

| `verify` | function | verify/2 |  |  |  |  |

| `verify` | function | verify/2 |  |  |  |  |

| `verify` | function | verify/2 |  |  |  |  |


### AshR2RML.VKG.Batch

| `bad_max` | function | bad_max/1 |  |  |  |  |

| `bad_options` | function | bad_options/1 |  |  |  |  |

| `do_run` | function | do_run/2 |  |  |  |  |

| `query` | function | query/2 |  |  |  |  |

| `run` | function | run/2 |  |  |  |  |

| `run` | function | run/2 |  |  |  |  |

| `run` | function | run/2 |  |  |  |  |

| `run` | function | run/2 |  |  |  |  |

| `run_request` | function | run_request/2 |  |  |  |  |

| `run_request` | function | run_request/2 |  |  |  |  |

| `whole` | function | whole/1 |  |  |  |  |


### AshR2RML.VKG.Catalog

| `fetch` | function | fetch/2 |  |  |  |  |

| `ids` | function | ids/1 |  |  |  |  |

| `load` | function | load/1 |  |  |  |  |

| `new` | function | new/1 |  |  |  |  |

| `scope_refusal` | function | scope_refusal/2 |  |  |  |  |

| `select` | function | select/2 |  |  |  |  |

| `select` | function | select/2 |  |  |  |  |

| `select_valid` | function | select_valid/2 |  |  |  |  |

| `snapshot` | function | snapshot/1 |  |  |  |  |

| `valid_ids` | function | valid_ids/1 |  |  |  |  |


### AshR2RML.VKG.Compatibility

| `check` | function | check/1 |  |  |  |  |

| `check` | function | check/1 |  |  |  |  |

| `compatible_pair?` | function | compatible_pair?/2 |  |  |  |  |

| `matrix` | function | matrix/1 |  |  |  |  |

| `observe_only` | function | observe_only/1 |  |  |  |  |

| `refusal` | function | refusal/3 |  |  |  |  |

| `structs` | function | structs/1 |  |  |  |  |

| `unique_graphs` | function | unique_graphs/1 |  |  |  |  |

| `unique_sources` | function | unique_sources/1 |  |  |  |  |

| `versions` | function | versions/1 |  |  |  |  |


### AshR2RML.VKG.Consumer.Engineering

| `snapshot` | function | snapshot/1 |  |  |  |  |


### AshR2RML.VKG.Consumer.GraphQL

| `connection` | function | connection/2 |  |  |  |  |

| `cursor` | function | cursor/3 |  |  |  |  |

| `decode` | function | decode/2 |  |  |  |  |

| `edge` | function | edge/3 |  |  |  |  |

| `end_cursor` | function | end_cursor/1 |  |  |  |  |

| `end_cursor` | function | end_cursor/1 |  |  |  |  |

| `invalid_cursor` | function | invalid_cursor/1 |  |  |  |  |

| `page` | function | page/2 |  |  |  |  |

| `page` | function | page/2 |  |  |  |  |

| `page` | function | page/2 |  |  |  |  |

| `page` | function | page/2 |  |  |  |  |

| `refuse` | function | refuse/3 |  |  |  |  |

| `result_prefix` | function | result_prefix/1 |  |  |  |  |

| `row_digest` | function | row_digest/1 |  |  |  |  |

| `start_index` | function | start_index/3 |  |  |  |  |

| `start_index` | function | start_index/3 |  |  |  |  |

| `start_index` | function | start_index/3 |  |  |  |  |

| `validate_first` | function | validate_first/1 |  |  |  |  |

| `validate_first` | function | validate_first/1 |  |  |  |  |


### AshR2RML.VKG.Contract

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `canonical_hash` | function | canonical_hash/1 |  |  |  |  |

| `capability_allowlist` | function | capability_allowlist/0 |  |  |  |  |

| `capability_refusal` | function | capability_refusal/1 |  |  |  |  |

| `digest` | function | digest/1 |  |  |  |  |

| `digest_refusal` | function | digest_refusal/1 |  |  |  |  |

| `exact_subject?` | function | exact_subject?/2 |  |  |  |  |

| `exact_subject?` | function | exact_subject?/2 |  |  |  |  |

| `identity` | function | identity/1 |  |  |  |  |

| `shape_refusal` | function | shape_refusal/3 |  |  |  |  |

| `validate_authority` | function | validate_authority/1 |  |  |  |  |

| `validate_authority` | function | validate_authority/1 |  |  |  |  |

| `validate_capabilities` | function | validate_capabilities/1 |  |  |  |  |

| `validate_capabilities` | function | validate_capabilities/1 |  |  |  |  |

| `validate_digest` | function | validate_digest/2 |  |  |  |  |

| `validate_digest` | function | validate_digest/2 |  |  |  |  |

| `validate_ontology` | function | validate_ontology/2 |  |  |  |  |

| `validate_ontology` | function | validate_ontology/2 |  |  |  |  |

| `validate_ontology` | function | validate_ontology/2 |  |  |  |  |

| `validate_path` | function | validate_path/2 |  |  |  |  |

| `validate_path` | function | validate_path/2 |  |  |  |  |

| `validate_standing` | function | validate_standing/1 |  |  |  |  |

| `validate_standing` | function | validate_standing/1 |  |  |  |  |

| `validate_text` | function | validate_text/2 |  |  |  |  |

| `validate_text` | function | validate_text/2 |  |  |  |  |

| `validate_version` | function | validate_version/1 |  |  |  |  |

| `validate_version` | function | validate_version/1 |  |  |  |  |


### AshR2RML.VKG.Engine.Ontop

| `execute` | function | execute/2 |  |  |  |  |

| `maybe_put` | function | maybe_put/3 |  |  |  |  |

| `maybe_put` | function | maybe_put/3 |  |  |  |  |


### AshR2RML.VKG.Executor

| `aggregate_standing` | function | aggregate_standing/2 |  |  |  |  |

| `bind_catalog` | function | bind_catalog/2 |  |  |  |  |

| `bound_refusal` | function | bound_refusal/2 |  |  |  |  |

| `call_engine` | function | call_engine/3 |  |  |  |  |

| `canonicalize_observation` | function | canonicalize_observation/2 |  |  |  |  |

| `catalog_intact` | function | catalog_intact/1 |  |  |  |  |

| `catalog_intact` | function | catalog_intact/1 |  |  |  |  |

| `catalog_matches_plan` | function | catalog_matches_plan/2 |  |  |  |  |

| `check_drift` | function | check_drift/2 |  |  |  |  |

| `check_engine` | function | check_engine/1 |  |  |  |  |

| `check_recorded_digest` | function | check_recorded_digest/2 |  |  |  |  |

| `check_running_bound` | function | check_running_bound/2 |  |  |  |  |

| `check_running_bound` | function | check_running_bound/2 |  |  |  |  |

| `check_stage_binding` | function | check_stage_binding/3 |  |  |  |  |

| `drift_result` | function | drift_result/3 |  |  |  |  |

| `drift_result` | function | drift_result/3 |  |  |  |  |

| `enforce_result_bound` | function | enforce_result_bound/2 |  |  |  |  |

| `execute` | function | execute/2 |  |  |  |  |

| `execute` | function | execute/2 |  |  |  |  |

| `execute` | function | execute/2 |  |  |  |  |

| `execute` | function | execute/2 |  |  |  |  |

| `fetch_bound_contract` | function | fetch_bound_contract/2 |  |  |  |  |

| `malformed` | function | malformed/3 |  |  |  |  |

| `merge` | function | merge/2 |  |  |  |  |

| `merge` | function | merge/2 |  |  |  |  |

| `merge_subject` | function | merge_subject/1 |  |  |  |  |

| `merge_values` | function | merge_values/2 |  |  |  |  |

| `merge_values` | function | merge_values/2 |  |  |  |  |

| `plan_refusal` | function | plan_refusal/3 |  |  |  |  |

| `read_bytes` | function | read_bytes/1 |  |  |  |  |

| `read_bytes` | function | read_bytes/1 |  |  |  |  |

| `replay` | function | replay/3 |  |  |  |  |

| `replay` | function | replay/3 |  |  |  |  |

| `row_identity` | function | row_identity/1 |  |  |  |  |

| `run` | function | run/5 |  |  |  |  |

| `run_stage` | function | run_stage/7 |  |  |  |  |

| `run_stages` | function | run_stages/4 |  |  |  |  |

| `safe_engine_call` | function | safe_engine_call/3 |  |  |  |  |

| `safe_extension` | function | safe_extension/1 |  |  |  |  |

| `semantic_sha256` | function | semantic_sha256/2 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `snapshot_stage` | function | snapshot_stage/1 |  |  |  |  |

| `stage_refusal` | function | stage_refusal/2 |  |  |  |  |

| `stages_match_catalog` | function | stages_match_catalog/2 |  |  |  |  |

| `validate_observation` | function | validate_observation/2 |  |  |  |  |

| `validate_observation` | function | validate_observation/2 |  |  |  |  |

| `with_stage_inputs` | function | with_stage_inputs/3 |  |  |  |  |

| `with_stage_inputs` | function | with_stage_inputs/3 |  |  |  |  |

| `write_files` | function | write_files/3 |  |  |  |  |

| `write_snapshot` | function | write_snapshot/2 |  |  |  |  |


### AshR2RML.VKG.Inspection

| `catalog` | function | catalog/1 |  |  |  |  |

| `session` | function | session/1 |  |  |  |  |

| `snapshot` | function | snapshot/1 |  |  |  |  |

| `snapshot` | function | snapshot/1 |  |  |  |  |


### AshR2RML.VKG.Manifest

| `capabilities` | function | capabilities/1 |  |  |  |  |

| `capabilities` | function | capabilities/1 |  |  |  |  |

| `capabilities` | function | capabilities/1 |  |  |  |  |

| `capability_refusal` | function | capability_refusal/1 |  |  |  |  |

| `contained` | function | contained/4 |  |  |  |  |

| `decode` | function | decode/2 |  |  |  |  |

| `default_root` | function | default_root/0 |  |  |  |  |

| `load` | function | load/2 |  |  |  |  |

| `load` | function | load/2 |  |  |  |  |

| `load` | function | load/2 |  |  |  |  |

| `load_all` | function | load_all/1 |  |  |  |  |

| `load_all` | function | load_all/1 |  |  |  |  |

| `load_all` | function | load_all/1 |  |  |  |  |

| `load_paths` | function | load_paths/2 |  |  |  |  |

| `optional_digest` | function | optional_digest/1 |  |  |  |  |

| `optional_digest` | function | optional_digest/1 |  |  |  |  |

| `optional_resolve` | function | optional_resolve/2 |  |  |  |  |

| `optional_resolve` | function | optional_resolve/2 |  |  |  |  |

| `read` | function | read/2 |  |  |  |  |

| `refusal` | function | refusal/3 |  |  |  |  |

| `resolve` | function | resolve/3 |  |  |  |  |

| `resolve` | function | resolve/3 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `snapshot` | function | snapshot/1 |  |  |  |  |

| `symlinked?` | function | symlinked?/2 |  |  |  |  |

| `version` | function | version/1 |  |  |  |  |

| `version` | function | version/1 |  |  |  |  |

| `version` | function | version/1 |  |  |  |  |


### AshR2RML.VKG.Metrics

| `from_session` | function | from_session/1 |  |  |  |  |


### AshR2RML.VKG.Planner

| `do_plan` | function | do_plan/3 |  |  |  |  |

| `ensure_capability` | function | ensure_capability/2 |  |  |  |  |

| `options_refusal` | function | options_refusal/1 |  |  |  |  |

| `plan` | function | plan/3 |  |  |  |  |

| `plan` | function | plan/3 |  |  |  |  |

| `plan` | function | plan/3 |  |  |  |  |

| `plan` | function | plan/3 |  |  |  |  |

| `plan_all` | function | plan_all/2 |  |  |  |  |

| `stage_for` | function | stage_for/1 |  |  |  |  |

| `valid_capability` | function | valid_capability/1 |  |  |  |  |


### AshR2RML.VKG.Provenance

| `attach` | function | attach/3 |  |  |  |  |

| `exact_source?` | function | exact_source?/2 |  |  |  |  |

| `row_hash` | function | row_hash/3 |  |  |  |  |

| `strip` | function | strip/1 |  |  |  |  |

| `subject` | function | subject/1 |  |  |  |  |


### AshR2RML.VKG.QueryPlan

| `authority?` | function | authority?/1 |  |  |  |  |

| `authority?` | function | authority?/1 |  |  |  |  |

| `canonical_stages` | function | canonical_stages/1 |  |  |  |  |

| `capability?` | function | capability?/1 |  |  |  |  |

| `common_capabilities` | function | common_capabilities/1 |  |  |  |  |

| `core` | function | core/1 |  |  |  |  |

| `digest?` | function | digest?/2 |  |  |  |  |

| `digest?` | function | digest?/2 |  |  |  |  |

| `hash` | function | hash/1 |  |  |  |  |

| `merge_mode?` | function | merge_mode?/1 |  |  |  |  |

| `merge_mode?` | function | merge_mode?/1 |  |  |  |  |

| `new` | function | new/4 |  |  |  |  |

| `new` | function | new/4 |  |  |  |  |

| `new` | function | new/4 |  |  |  |  |

| `non_empty_ids?` | function | non_empty_ids?/1 |  |  |  |  |

| `non_empty_ids?` | function | non_empty_ids?/1 |  |  |  |  |

| `ontology_binding` | function | ontology_binding/1 |  |  |  |  |

| `ontology_binding_matches?` | function | ontology_binding_matches?/1 |  |  |  |  |

| `ontology_consistent?` | function | ontology_consistent?/1 |  |  |  |  |

| `plan_id` | function | plan_id/1 |  |  |  |  |

| `positive_integer?` | function | positive_integer?/2 |  |  |  |  |

| `positive_integer?` | function | positive_integer?/2 |  |  |  |  |

| `refusal` | function | refusal/3 |  |  |  |  |

| `stage_capabilities?` | function | stage_capabilities?/1 |  |  |  |  |

| `stages_match?` | function | stages_match?/2 |  |  |  |  |

| `stages_match?` | function | stages_match?/2 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |


### AshR2RML.VKG.Receipt

| `build` | function | build/4 |  |  |  |  |

| `evidence_digests` | function | evidence_digests/1 |  |  |  |  |


### AshR2RML.VKG.Registry

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit_each` | function | admit_each/1 |  |  |  |  |

| `consistent_graphs` | function | consistent_graphs/1 |  |  |  |  |

| `consistent_sources` | function | consistent_sources/1 |  |  |  |  |

| `digest` | function | digest/1 |  |  |  |  |

| `fetch` | function | fetch/2 |  |  |  |  |

| `fetch` | function | fetch/2 |  |  |  |  |

| `fetch` | function | fetch/2 |  |  |  |  |

| `refusal` | function | refusal/3 |  |  |  |  |

| `unique_ids` | function | unique_ids/1 |  |  |  |  |


### AshR2RML.VKG.Replay


### AshR2RML.VKG.Result

| `build` | function | build/3 |  |  |  |  |

| `compute_sha256` | function | compute_sha256/3 |  |  |  |  |

| `equivalent?` | function | equivalent?/2 |  |  |  |  |

| `normal_form?` | function | normal_form?/1 |  |  |  |  |

| `normalize_row` | function | normalize_row/1 |  |  |  |  |

| `normalize_row` | function | normalize_row/1 |  |  |  |  |

| `normalize_value` | function | normalize_value/1 |  |  |  |  |

| `normalize_value` | function | normalize_value/1 |  |  |  |  |

| `normalize_value` | function | normalize_value/1 |  |  |  |  |

| `normalize_value` | function | normalize_value/1 |  |  |  |  |

| `normalize_value` | function | normalize_value/1 |  |  |  |  |

| `normalize_value` | function | normalize_value/1 |  |  |  |  |

| `normalize_value` | function | normalize_value/1 |  |  |  |  |

| `normalize_value` | function | normalize_value/1 |  |  |  |  |

| `normalize_value` | function | normalize_value/1 |  |  |  |  |

| `refusal` | function | refusal/3 |  |  |  |  |

| `row_sort_key` | function | row_sort_key/1 |  |  |  |  |

| `source_counts` | function | source_counts/1 |  |  |  |  |

| `source_index` | function | source_index/1 |  |  |  |  |

| `standings` | function | standings/0 |  |  |  |  |

| `subject_index` | function | subject_index/1 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |


### AshR2RML.VKG.SA2AEvidence

| `app_version` | function | app_version/0 |  |  |  |  |

| `digest` | function | digest/2 |  |  |  |  |

| `digest` | function | digest/2 |  |  |  |  |

| `digest` | function | digest/2 |  |  |  |  |

| `encode!` | function | encode!/1 |  |  |  |  |

| `fetch` | function | fetch/2 |  |  |  |  |

| `from_source` | function | from_source/2 |  |  |  |  |

| `from_source` | function | from_source/2 |  |  |  |  |

| `from_source` | function | from_source/2 |  |  |  |  |

| `non_empty` | function | non_empty/2 |  |  |  |  |

| `non_empty` | function | non_empty/2 |  |  |  |  |

| `non_empty_value?` | function | non_empty_value?/1 |  |  |  |  |

| `put_optional_provenance` | function | put_optional_provenance/2 |  |  |  |  |

| `put_optional_provenance` | function | put_optional_provenance/2 |  |  |  |  |

| `put_optional_provenance` | function | put_optional_provenance/2 |  |  |  |  |

| `receipt_digest` | function | receipt_digest/1 |  |  |  |  |

| `receipt_digest` | function | receipt_digest/1 |  |  |  |  |

| `receipt_digest` | function | receipt_digest/1 |  |  |  |  |

| `receipt_digest` | function | receipt_digest/1 |  |  |  |  |

| `refusal` | function | refusal/3 |  |  |  |  |

| `replay_identity` | function | replay_identity/2 |  |  |  |  |

| `seal` | function | seal/1 |  |  |  |  |

| `sha256?` | function | sha256?/1 |  |  |  |  |

| `stringify` | function | stringify/1 |  |  |  |  |

| `valid_source?` | function | valid_source?/0 |  |  |  |  |

| `valid_source?` | function | valid_source?/1 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |


### AshR2RML.VKG.Serializer

| `canonical_json` | function | canonical_json/1 |  |  |  |  |

| `decode_object` | function | decode_object/2 |  |  |  |  |

| `decode_receipt` | function | decode_receipt/1 |  |  |  |  |

| `decode_receipt` | function | decode_receipt/1 |  |  |  |  |

| `decode_result` | function | decode_result/1 |  |  |  |  |

| `decode_result` | function | decode_result/1 |  |  |  |  |

| `decode_value` | function | decode_value/1 |  |  |  |  |

| `decode_value` | function | decode_value/1 |  |  |  |  |

| `decode_value` | function | decode_value/1 |  |  |  |  |

| `decode_value` | function | decode_value/1 |  |  |  |  |

| `decode_value` | function | decode_value/1 |  |  |  |  |

| `decode_value` | function | decode_value/1 |  |  |  |  |

| `decode_value` | function | decode_value/1 |  |  |  |  |

| `decode_value` | function | decode_value/1 |  |  |  |  |

| `decode_value` | function | decode_value/1 |  |  |  |  |

| `decode_value` | function | decode_value/1 |  |  |  |  |

| `digest` | function | digest/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode_members` | function | encode_members/1 |  |  |  |  |

| `encode_pairs` | function | encode_pairs/1 |  |  |  |  |

| `encode_receipt!` | function | encode_receipt!/1 |  |  |  |  |

| `encode_result!` | function | encode_result!/1 |  |  |  |  |

| `encode_session!` | function | encode_session!/1 |  |  |  |  |

| `enum` | function | enum/4 |  |  |  |  |

| `fields` | function | fields/3 |  |  |  |  |

| `key_string` | function | key_string/1 |  |  |  |  |

| `key_string` | function | key_string/1 |  |  |  |  |

| `key_string` | function | key_string/1 |  |  |  |  |

| `plain_keys?` | function | plain_keys?/1 |  |  |  |  |

| `receipt` | function | receipt/1 |  |  |  |  |

| `refuse` | function | refuse/3 |  |  |  |  |

| `reserved_keys?` | function | reserved_keys?/1 |  |  |  |  |

| `result` | function | result/1 |  |  |  |  |

| `session` | function | session/1 |  |  |  |  |

| `signature` | function | signature/1 |  |  |  |  |

| `signature` | function | signature/1 |  |  |  |  |

| `signature` | function | signature/1 |  |  |  |  |

| `signature` | function | signature/1 |  |  |  |  |

| `stringify` | function | stringify/1 |  |  |  |  |

| `tagged` | function | tagged/2 |  |  |  |  |

| `verify_receipt_json` | function | verify_receipt_json/4 |  |  |  |  |


### AshR2RML.VKG.Session

| `check_catalog` | function | check_catalog/1 |  |  |  |  |

| `check_reconstruction` | function | check_reconstruction/1 |  |  |  |  |

| `compare_rebuilt` | function | compare_rebuilt/2 |  |  |  |  |

| `new` | function | new/0 |  |  |  |  |

| `summary` | function | summary/1 |  |  |  |  |

| `verify` | function | verify/2 |  |  |  |  |


### AshR2RML.VKG.SourceIdentity

| `absolute_identity?` | function | absolute_identity?/1 |  |  |  |  |

| `absolute_identity?` | function | absolute_identity?/1 |  |  |  |  |

| `fetch` | function | fetch/2 |  |  |  |  |

| `fingerprint` | function | fingerprint/1 |  |  |  |  |

| `new` | function | new/1 |  |  |  |  |

| `new` | function | new/1 |  |  |  |  |

| `non_empty?` | function | non_empty?/1 |  |  |  |  |

| `refusal` | function | refusal/3 |  |  |  |  |

| `same?` | function | same?/2 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `verify` | function | verify/2 |  |  |  |  |


### AshR2RML.VKGCase

| `catalog` | function | catalog/1 |  |  |  |  |

| `collect_atoms` | function | collect_atoms/2 |  |  |  |  |

| `collect_atoms` | function | collect_atoms/2 |  |  |  |  |

| `collect_atoms` | function | collect_atoms/2 |  |  |  |  |

| `collect_atoms` | function | collect_atoms/2 |  |  |  |  |

| `contract` | function | contract/2 |  |  |  |  |

| `plan` | function | plan/1 |  |  |  |  |

| `refusal_codes` | function | refusal_codes/0 |  |  |  |  |

| `type_atoms` | function | type_atoms/2 |  |  |  |  |


### AshR2RML.Validation


### AshR2RML.VerifyMapping

| `absolute_iri` | function | absolute_iri/2 |  |  |  |  |

| `absolute_iri` | function | absolute_iri/2 |  |  |  |  |

| `exactly_one_logical_table` | function | exactly_one_logical_table/2 |  |  |  |  |

| `known_attributes` | function | known_attributes/3 |  |  |  |  |

| `known_relationships` | function | known_relationships/2 |  |  |  |  |

| `optional_absolute_iri` | function | optional_absolute_iri/2 |  |  |  |  |

| `optional_absolute_iri` | function | optional_absolute_iri/2 |  |  |  |  |

| `present?` | function | present?/1 |  |  |  |  |

| `primary_key_in_template` | function | primary_key_in_template/2 |  |  |  |  |

| `primary_key_in_template` | function | primary_key_in_template/2 |  |  |  |  |

| `unique_attribute_mapping` | function | unique_attribute_mapping/2 |  |  |  |  |

| `valid_predicates` | function | valid_predicates/3 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |


### AshR2RML.VerifyMapping.Alignment

| `verify` | function | verify/1 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |


### Candidate


### Capability


### Cell

| `capabilities_allowed?` | function | capabilities_allowed?/2 |  |  |  |  |

| `cells` | function | cells/2 |  |  |  |  |

| `country_for` | function | country_for/1 |  |  |  |  |

| `hash` | function | hash/1 |  |  |  |  |

| `rendezvous_score` | function | rendezvous_score/2 |  |  |  |  |

| `residency_allowed?` | function | residency_allowed?/4 |  |  |  |  |

| `route` | function | route/3 |  |  |  |  |


### Cell


### ChoiceGraph

| `serialize_node` | function | serialize_node/2 |  |  |  |  |

| `serialize_node` | function | serialize_node/2 |  |  |  |  |

| `serialize_node` | function | serialize_node/2 |  |  |  |  |

| `to_owl_turtle` | function | to_owl_turtle/2 |  |  |  |  |


### ConformanceReport

| `standard_e2o_qualifiers` | function | standard_e2o_qualifiers/0 |  |  |  |  |

| `standard_lifecycles` | function | standard_lifecycles/0 |  |  |  |  |

| `standard_o2o_qualifiers` | function | standard_o2o_qualifiers/0 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |


### Constraint


### Dimension


### DoReceipt

| `admit` | function | admit/3 |  |  |  |  |

| `authorize_do` | function | authorize_do/2 |  |  |  |  |

| `constraint` | function | constraint/4 |  |  |  |  |

| `default_assignment` | function | default_assignment/0 |  |  |  |  |

| `default_profile` | function | default_profile/0 |  |  |  |  |

| `design_space` | function | design_space/0 |  |  |  |  |

| `dimension` | function | dimension/3 |  |  |  |  |

| `operational_ready?` | function | operational_ready?/1 |  |  |  |  |

| `operational_ready?` | function | operational_ready?/1 |  |  |  |  |

| `profile_sha256` | function | profile_sha256/1 |  |  |  |  |

| `validate_profile` | function | validate_profile/1 |  |  |  |  |

| `verify_evidence` | function | verify_evidence/3 |  |  |  |  |


### EnumerationReceipt


### Event


### Evidence


### FakeEngine

| `execute` | function | execute/2 |  |  |  |  |


### Log


### Mix.Tasks.AshR2rml.Gen.SemanticTypes

| `igniter` | function | igniter/1 |  |  |  |  |


### Mix.Tasks.AshR2rml.Gen.SemanticTypes

| `run` | function | run/1 |  |  |  |  |


### Mix.Tasks.AshR2rml.GenerateDocs

| `run` | function | run/1 |  |  |  |  |


### Mix.Tasks.AshR2rml.Install

| `Mix.Tasks.AshR2rml.Install` | ash_resource |  |  |  |  |  |

| `add_starter_dsl_block` | function | add_starter_dsl_block/2 |  |  |  |  |

| `igniter` | function | igniter/1 |  |  |  |  |

| `info` | function | info/2 |  |  |  |  |


### Mix.Tasks.AshR2rml.Install

| `run` | function | run/1 |  |  |  |  |


### Mix.Tasks.AshR2rml.TestLivebooks

| `run` | function | run/1 |  |  |  |  |


### Mix.Tasks.AshR2rml.Types.Check

| `run` | function | run/1 |  |  |  |  |


### Mix.Tasks.AshR2rml.Types.Diff

| `run` | function | run/1 |  |  |  |  |

| `run` | function | run/1 |  |  |  |  |


### Mix.Tasks.AshR2rml.Types.Inspect

| `run` | function | run/1 |  |  |  |  |

| `run` | function | run/1 |  |  |  |  |


### Mix.Tasks.AshR2rml.Types.Manifest

| `run` | function | run/1 |  |  |  |  |


### Mix.Tasks.AshR2rml.Types.Plan

| `run` | function | run/1 |  |  |  |  |


### Mix.Tasks.AshR2rml.Types.Sync

| `run` | function | run/1 |  |  |  |  |


### Mix.Tasks.AshR2rml.Types.Verify

| `run` | function | run/1 |  |  |  |  |


### MyApp.Person

| `MyApp.Person` | ash_resource |  |  |  |  |  |

| `receipt` | function | receipt/1 |  |  |  |  |


### MyApp.Schema

| `__r2rml_domains__` | function | __r2rml_domains__/0 |  |  |  |  |

| `assert_read_only!` | function | assert_read_only!/2 |  |  |  |  |

| `canonical_sdl` | function | canonical_sdl/1 |  |  |  |  |

| `receipt` | function | receipt/1 |  |  |  |  |

| `resources` | function | resources/1 |  |  |  |  |

| `schema_sha` | function | schema_sha/1 |  |  |  |  |

| `sdl` | function | sdl/1 |  |  |  |  |


### Object


### Observation


### PartialOrder


### Plan


### Plan

| `cells` | function | cells/4 |  |  |  |  |

| `contains_secret?` | function | contains_secret?/1 |  |  |  |  |

| `maybe_refuse` | function | maybe_refuse/3 |  |  |  |  |

| `maybe_refuse` | function | maybe_refuse/3 |  |  |  |  |

| `plan` | function | plan/3 |  |  |  |  |

| `role` | function | role/5 |  |  |  |  |

| `roles` | function | roles/1 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |


### Profile


### Receipt

| `compile` | function | compile/2 |  |  |  |  |


### RecordedEngine

| `compare` | function | compare/2 |  |  |  |  |

| `execute` | function | execute/2 |  |  |  |  |

| `reconstruct` | function | reconstruct/2 |  |  |  |  |

| `reconstruct` | function | reconstruct/2 |  |  |  |  |

| `refuse` | function | refuse/3 |  |  |  |  |

| `verify` | function | verify/5 |  |  |  |  |


### Refusal


### Refusal


### RefusingEngine

| `execute` | function | execute/2 |  |  |  |  |


### Relationship


### Result

| `admitted_candidates` | function | admitted_candidates/1 |  |  |  |  |

| `build_plan` | function | build_plan/3 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical_relationship` | function | canonical_relationship/1 |  |  |  |  |

| `exact_binding` | function | exact_binding/2 |  |  |  |  |

| `falsifiers_clear` | function | falsifiers_clear/2 |  |  |  |  |

| `observe` | function | observe/2 |  |  |  |  |

| `observe` | function | observe/2 |  |  |  |  |

| `plans` | function | plans/2 |  |  |  |  |

| `plans` | function | plans/2 |  |  |  |  |

| `required_checks_pass` | function | required_checks_pass/2 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |


### Role


### SelectionReceipt

| `enumerate` | function | enumerate/2 |  |  |  |  |

| `logical_cardinality` | function | logical_cardinality/2 |  |  |  |  |

| `new` | function | new/3 |  |  |  |  |


### Space


### Transition



<!-- AGENT-FORBIDDEN-END -->

## Signature/type/default/errors table

<!-- RIGID table: header order is fixed; rows come only from the query. -->

| Item | Type | Signature | Params | Defaults | Errors | Invariants |
|------|------|-----------|--------|----------|--------|------------|

| `admit` | function | admit/2 |  |  |  |  |

| `cap` | function | cap/6 |  |  |  |  |

| `catalog` | function | catalog/0 |  |  |  |  |

| `classify` | function | classify/2 |  |  |  |  |

| `closure` | function | closure/1 |  |  |  |  |

| `evidence_plan` | function | evidence_plan/2 |  |  |  |  |

| `expand` | function | expand/3 |  |  |  |  |

| `expand` | function | expand/3 |  |  |  |  |

| `fetch` | function | fetch/3 |  |  |  |  |

| `graph_sha256` | function | graph_sha256/0 |  |  |  |  |

| `normalize_observation` | function | normalize_observation/1 |  |  |  |  |

| `normalize_observation` | function | normalize_observation/1 |  |  |  |  |

| `valid_observation?` | function | valid_observation?/2 |  |  |  |  |

| `admit_knowledge_hooks` | function | admit_knowledge_hooks/2 |  |  |  |  |

| `compile_api_bundle` | function | compile_api_bundle/2 |  |  |  |  |

| `compile_bundle` | function | compile_bundle/2 |  |  |  |  |

| `compile_jsonld` | function | compile_jsonld/2 |  |  |  |  |

| `compile_jsonld_bundle` | function | compile_jsonld_bundle/2 |  |  |  |  |

| `compile_knowledge_hook_specs` | function | compile_knowledge_hook_specs/1 |  |  |  |  |

| `compile_knowledge_hooks_bundle` | function | compile_knowledge_hooks_bundle/2 |  |  |  |  |

| `compile_knowledge_hooks_turtle_bundle` | function | compile_knowledge_hooks_turtle_bundle/2 |  |  |  |  |

| `compile_production` | function | compile_production/2 |  |  |  |  |

| `compile_turtle` | function | compile_turtle/2 |  |  |  |  |

| `compile_turtle_bundle` | function | compile_turtle_bundle/2 |  |  |  |  |

| `evaluate_knowledge_hook_promotion` | function | evaluate_knowledge_hook_promotion/3 |  |  |  |  |

| `evaluate_knowledge_hooks` | function | evaluate_knowledge_hooks/2 |  |  |  |  |

| `ingest_jsonld` | function | ingest_jsonld/2 |  |  |  |  |

| `ingest_knowledge_hooks_turtle` | function | ingest_knowledge_hooks_turtle/2 |  |  |  |  |

| `ingest_turtle` | function | ingest_turtle/2 |  |  |  |  |

| `plan_sparql` | function | plan_sparql/2 |  |  |  |  |

| `production_admit` | function | production_admit/3 |  |  |  |  |

| `production_candidates` | function | production_candidates/1 |  |  |  |  |

| `project_knowledge_hook_target` | function | project_knowledge_hook_target/1 |  |  |  |  |

| `schedule_knowledge_hook_specs` | function | schedule_knowledge_hook_specs/1 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `datatype_projection` | function | datatype_projection/1 |  |  |  |  |

| `normalize_attributes` | function | normalize_attributes/1 |  |  |  |  |

| `normalize_attributes` | function | normalize_attributes/1 |  |  |  |  |

| `normalize_identities` | function | normalize_identities/1 |  |  |  |  |

| `normalize_resource` | function | normalize_resource/1 |  |  |  |  |

| `normalize_resource` | function | normalize_resource/1 |  |  |  |  |

| `normalize_resources` | function | normalize_resources/1 |  |  |  |  |

| `normalize_resources` | function | normalize_resources/1 |  |  |  |  |

| `admit_input` | function | admit_input/2 |  |  |  |  |

| `admit_profile` | function | admit_profile/1 |  |  |  |  |

| `admit_profile` | function | admit_profile/1 |  |  |  |  |

| `defaults` | function | defaults/0 |  |  |  |  |

| `get` | function | get/3 |  |  |  |  |

| `get_option` | function | get_option/3 |  |  |  |  |

| `get_option` | function | get_option/3 |  |  |  |  |

| `get_option` | function | get_option/3 |  |  |  |  |

| `input_bytes` | function | input_bytes/1 |  |  |  |  |

| `input_bytes` | function | input_bytes/1 |  |  |  |  |

| `integer_or_zero` | function | integer_or_zero/1 |  |  |  |  |

| `integer_or_zero` | function | integer_or_zero/1 |  |  |  |  |

| `max_nested` | function | max_nested/2 |  |  |  |  |

| `normalized_limits` | function | normalized_limits/1 |  |  |  |  |

| `normalized_limits` | function | normalized_limits/1 |  |  |  |  |

| `total_members` | function | total_members/1 |  |  |  |  |

| `generate` | function | generate/0 |  |  |  |  |

| `attach_parity_witness` | function | attach_parity_witness/3 |  |  |  |  |

| `attach_parity_witness` | function | attach_parity_witness/3 |  |  |  |  |

| `attribute_column` | function | attribute_column/2 |  |  |  |  |

| `authorize_cutover` | function | authorize_cutover/2 |  |  |  |  |

| `canonical_ir` | function | canonical_ir/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile_resources` | function | compile_resources/1 |  |  |  |  |

| `convert_references` | function | convert_references/2 |  |  |  |  |

| `cutover_ready?` | function | cutover_ready?/0 |  |  |  |  |

| `cutover_ready?` | function | cutover_ready?/1 |  |  |  |  |

| `do_closure` | function | do_closure/3 |  |  |  |  |

| `do_closure` | function | do_closure/3 |  |  |  |  |

| `explore` | function | explore/1 |  |  |  |  |

| `projection_refusals` | function | projection_refusals/1 |  |  |  |  |

| `public_refusal_compilation` | function | public_refusal_compilation/2 |  |  |  |  |

| `receipt` | function | receipt/8 |  |  |  |  |

| `refusal_compilation` | function | refusal_compilation/2 |  |  |  |  |

| `refusal_receipt` | function | refusal_receipt/2 |  |  |  |  |

| `render_all` | function | render_all/2 |  |  |  |  |

| `render_storage_ddl` | function | render_storage_ddl/2 |  |  |  |  |

| `render_storage_ddl` | function | render_storage_ddl/2 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `storage_map` | function | storage_map/2 |  |  |  |  |

| `storage_render_step` | function | storage_render_step/1 |  |  |  |  |

| `storage_render_step` | function | storage_render_step/1 |  |  |  |  |

| `backend` | function | backend/1 |  |  |  |  |

| `default_table_name` | function | default_table_name/1 |  |  |  |  |

| `ets_table_name` | function | ets_table_name/1 |  |  |  |  |

| `generic_table_name` | function | generic_table_name/1 |  |  |  |  |

| `infer_join_columns` | function | infer_join_columns/2 |  |  |  |  |

| `postgres_table_name` | function | postgres_table_name/1 |  |  |  |  |

| `schema_name` | function | schema_name/1 |  |  |  |  |

| `table_name` | function | table_name/1 |  |  |  |  |

| `absolute_iri?` | function | absolute_iri?/1 |  |  |  |  |

| `builtin_contracts` | function | builtin_contracts/0 |  |  |  |  |

| `builtin_storage` | function | builtin_storage/1 |  |  |  |  |

| `enum_type?` | function | enum_type?/1 |  |  |  |  |

| `legacy_literal_type?` | function | legacy_literal_type?/1 |  |  |  |  |

| `normalize_ash_type` | function | normalize_ash_type/1 |  |  |  |  |

| `normalize_ash_type` | function | normalize_ash_type/1 |  |  |  |  |

| `resolve` | function | resolve/3 |  |  |  |  |

| `semantic_contract` | function | semantic_contract/1 |  |  |  |  |

| `semantic_contract` | function | semantic_contract/1 |  |  |  |  |

| `semantic_literal?` | function | semantic_literal?/1 |  |  |  |  |

| `semantic_literal?` | function | semantic_literal?/1 |  |  |  |  |

| `semantic_storage` | function | semantic_storage/1 |  |  |  |  |

| `supported?` | function | supported?/1 |  |  |  |  |

| `default_iterations` | function | default_iterations/0 |  |  |  |  |

| `diff` | function | diff/2 |  |  |  |  |

| `root_digest` | function | root_digest/1 |  |  |  |  |

| `spec_budget_ms` | function | spec_budget_ms/0 |  |  |  |  |

| `triple_set` | function | triple_set/1 |  |  |  |  |

| `admit` | function | admit/2 |  |  |  |  |

| `frontier` | function | frontier/2 |  |  |  |  |

| `select` | function | select/1 |  |  |  |  |

| `select` | function | select/3 |  |  |  |  |

| `storage_candidates` | function | storage_candidates/1 |  |  |  |  |

| `storage_candidates` | function | storage_candidates/1 |  |  |  |  |

| `storage_candidates` | function | storage_candidates/1 |  |  |  |  |

| `equivalent?` | function | equivalent?/3 |  |  |  |  |

| `narrow` | function | narrow/2 |  |  |  |  |

| `narrow` | function | narrow/2 |  |  |  |  |

| `normalize` | function | normalize/2 |  |  |  |  |

| `normalize_candidate` | function | normalize_candidate/1 |  |  |  |  |

| `normalize_candidate` | function | normalize_candidate/1 |  |  |  |  |

| `normalize_candidate` | function | normalize_candidate/1 |  |  |  |  |

| `require_nonempty` | function | require_nonempty/2 |  |  |  |  |

| `require_nonempty` | function | require_nonempty/2 |  |  |  |  |

| `require_selected` | function | require_selected/2 |  |  |  |  |

| `require_subset` | function | require_subset/3 |  |  |  |  |

| `select` | function | select/3 |  |  |  |  |

| `admit_receipt_reuse` | function | admit_receipt_reuse/2 |  |  |  |  |

| `attach_parity_witness` | function | attach_parity_witness/3 |  |  |  |  |

| `authorize_cutover` | function | authorize_cutover/2 |  |  |  |  |

| `bind_verification_environment` | function | bind_verification_environment/2 |  |  |  |  |

| `classify_file_error` | function | classify_file_error/1 |  |  |  |  |

| `classify_file_error` | function | classify_file_error/1 |  |  |  |  |

| `compile` | function | compile/1 |  |  |  |  |

| `cutover_ready?` | function | cutover_ready?/1 |  |  |  |  |

| `drift` | function | drift/2 |  |  |  |  |

| `envelope` | function | envelope/3 |  |  |  |  |

| `get` | function | get/3 |  |  |  |  |

| `incremental_plan` | function | incremental_plan/2 |  |  |  |  |

| `maybe_add` | function | maybe_add/3 |  |  |  |  |

| `maybe_add` | function | maybe_add/3 |  |  |  |  |

| `present_hash?` | function | present_hash?/1 |  |  |  |  |

| `receipt_reusable?` | function | receipt_reusable?/2 |  |  |  |  |

| `refresh` | function | refresh/1 |  |  |  |  |

| `session_identity` | function | session_identity/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical_ocel_event` | function | canonical_ocel_event/1 |  |  |  |  |

| `execution_id` | function | execution_id/1 |  |  |  |  |

| `execution_id` | function | execution_id/1 |  |  |  |  |

| `get` | function | get/2 |  |  |  |  |

| `get` | function | get/2 |  |  |  |  |

| `id` | function | id/1 |  |  |  |  |

| `id` | function | id/1 |  |  |  |  |

| `id` | function | id/1 |  |  |  |  |

| `id` | function | id/1 |  |  |  |  |

| `id` | function | id/1 |  |  |  |  |

| `normalize_e2o` | function | normalize_e2o/1 |  |  |  |  |

| `normalize_e2o` | function | normalize_e2o/1 |  |  |  |  |

| `normalize_run_object` | function | normalize_run_object/1 |  |  |  |  |

| `normalize_run_object` | function | normalize_run_object/1 |  |  |  |  |

| `ocel_trace_id` | function | ocel_trace_id/2 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `admit_environment` | function | admit_environment/1 |  |  |  |  |

| `admit_environment` | function | admit_environment/1 |  |  |  |  |

| `compile_for_environments` | function | compile_for_environments/3 |  |  |  |  |

| `compile_for_environments` | function | compile_for_environments/3 |  |  |  |  |

| `compile_for_environments` | function | compile_for_environments/3 |  |  |  |  |

| `extensions` | function | extensions/0 |  |  |  |  |

| `features` | function | features/1 |  |  |  |  |

| `format` | function | format/2 |  |  |  |  |

| `build_system_seed` | function | build_system_seed/1 |  |  |  |  |

| `compile_fortune5_bundle` | function | compile_fortune5_bundle/0 |  |  |  |  |

| `domain` | function | domain/0 |  |  |  |  |

| `render_fortune5_r2rml` | function | render_fortune5_r2rml/0 |  |  |  |  |

| `resources` | function | resources/0 |  |  |  |  |

| `types` | function | types/0 |  |  |  |  |

| `AshR2RML.Fortune5.Calculations.UptimeSla` | ash_resource |  |  |  |  |  |

| `calculate` | function | calculate/3 |  |  |  |  |

| `AshR2RML.Fortune5.CloudRegion` | ash_resource |  |  |  |  |  |

| `AshR2RML.Fortune5.Cluster` | ash_resource |  |  |  |  |  |

| `AshR2RML.Fortune5.CredentialGrant` | ash_resource |  |  |  |  |  |

| `AshR2RML.Fortune5.DeploymentPlan` | ash_resource |  |  |  |  |  |

| `AshR2RML.Fortune5.DeploymentPlanService` | ash_resource |  |  |  |  |  |

| `build_complete_evidence_bundle` | function | build_complete_evidence_bundle/1 |  |  |  |  |

| `build_dcat_catalog` | function | build_dcat_catalog/1 |  |  |  |  |

| `build_earl_assertion` | function | build_earl_assertion/1 |  |  |  |  |

| `build_prov_lineage` | function | build_prov_lineage/1 |  |  |  |  |

| `build_sosa_observation` | function | build_sosa_observation/1 |  |  |  |  |

| `emit_ocel2_multigraph` | function | emit_ocel2_multigraph/1 |  |  |  |  |

| `random_id` | function | random_id/0 |  |  |  |  |

| `standard_prefixes` | function | standard_prefixes/0 |  |  |  |  |

| `AshR2RML.Fortune5.IncidentTicket` | ash_resource |  |  |  |  |  |

| `AshR2RML.Fortune5.LedgerAccount` | ash_resource |  |  |  |  |  |

| `AshR2RML.Fortune5.PaymentGateway` | ash_resource |  |  |  |  |  |

| `events` | function | events/0 |  |  |  |  |

| `record_event` | function | record_event/1 |  |  |  |  |

| `reset_events` | function | reset_events/0 |  |  |  |  |

| `run_blue_green` | function | run_blue_green/2 |  |  |  |  |

| `run_credential_rotation` | function | run_credential_rotation/2 |  |  |  |  |

| `run_disaster_recovery` | function | run_disaster_recovery/2 |  |  |  |  |

| `record` | function | record/1 |  |  |  |  |

| `reset` | function | reset/0 |  |  |  |  |

| `start_link` | function | start_link/1 |  |  |  |  |

| `stop` | function | stop/0 |  |  |  |  |

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `undo` | function | undo/4 |  |  |  |  |

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `undo` | function | undo/4 |  |  |  |  |

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `undo` | function | undo/4 |  |  |  |  |

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `undo` | function | undo/4 |  |  |  |  |

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `undo` | function | undo/4 |  |  |  |  |

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `undo` | function | undo/4 |  |  |  |  |

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `undo` | function | undo/4 |  |  |  |  |

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `undo` | function | undo/4 |  |  |  |  |

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `undo` | function | undo/4 |  |  |  |  |

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `undo` | function | undo/4 |  |  |  |  |

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `undo` | function | undo/4 |  |  |  |  |

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `undo` | function | undo/4 |  |  |  |  |

| `AshR2RML.Fortune5.ServiceInstance` | ash_resource |  |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `dump_to_embedded` | function | dump_to_embedded/2 |  |  |  |  |

| `dump_to_embedded` | function | dump_to_embedded/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `from_rdf_lexical` | function | from_rdf_lexical/1 |  |  |  |  |

| `storage_type` | function | storage_type/1 |  |  |  |  |

| `to_rdf_lexical` | function | to_rdf_lexical/1 |  |  |  |  |

| `values` | function | values/0 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `dump_to_embedded` | function | dump_to_embedded/2 |  |  |  |  |

| `dump_to_embedded` | function | dump_to_embedded/2 |  |  |  |  |

| `dump_to_embedded` | function | dump_to_embedded/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `from_rdf_lexical` | function | from_rdf_lexical/1 |  |  |  |  |

| `storage_type` | function | storage_type/1 |  |  |  |  |

| `to_decimal` | function | to_decimal/1 |  |  |  |  |

| `to_decimal` | function | to_decimal/1 |  |  |  |  |

| `to_decimal` | function | to_decimal/1 |  |  |  |  |

| `to_decimal` | function | to_decimal/1 |  |  |  |  |

| `to_decimal` | function | to_decimal/1 |  |  |  |  |

| `to_rdf_lexical` | function | to_rdf_lexical/1 |  |  |  |  |

| `to_rdf_lexical` | function | to_rdf_lexical/1 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `dump_to_embedded` | function | dump_to_embedded/2 |  |  |  |  |

| `dump_to_embedded` | function | dump_to_embedded/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `from_rdf_lexical` | function | from_rdf_lexical/1 |  |  |  |  |

| `parse_ip` | function | parse_ip/1 |  |  |  |  |

| `storage_type` | function | storage_type/1 |  |  |  |  |

| `to_rdf_lexical` | function | to_rdf_lexical/1 |  |  |  |  |

| `valid_cidr?` | function | valid_cidr?/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `evaluation_execution` | function | evaluation_execution/1 |  |  |  |  |

| `evaluation_execution` | function | evaluation_execution/1 |  |  |  |  |

| `evaluation_execution` | function | evaluation_execution/1 |  |  |  |  |

| `evaluation_execution` | function | evaluation_execution/1 |  |  |  |  |

| `evaluation_observation_count` | function | evaluation_observation_count/1 |  |  |  |  |

| `evaluation_observation_count` | function | evaluation_observation_count/1 |  |  |  |  |

| `evaluation_observation_count` | function | evaluation_observation_count/1 |  |  |  |  |

| `evaluation_observation_count` | function | evaluation_observation_count/1 |  |  |  |  |

| `evaluation_observation_state` | function | evaluation_observation_state/2 |  |  |  |  |

| `evaluation_observation_state` | function | evaluation_observation_state/2 |  |  |  |  |

| `evidence_refusal` | function | evidence_refusal/4 |  |  |  |  |

| `fingerprint` | function | fingerprint/1 |  |  |  |  |

| `from_knowledge_hooks` | function | from_knowledge_hooks/4 |  |  |  |  |

| `from_knowledge_hooks` | function | from_knowledge_hooks/4 |  |  |  |  |

| `from_knowledge_hooks` | function | from_knowledge_hooks/4 |  |  |  |  |

| `inspect_type` | function | inspect_type/1 |  |  |  |  |

| `inspect_type` | function | inspect_type/1 |  |  |  |  |

| `producer_head` | function | producer_head/1 |  |  |  |  |

| `refusal` | function | refusal/3 |  |  |  |  |

| `reject_duplicate` | function | reject_duplicate/4 |  |  |  |  |

| `replay_matches?` | function | replay_matches?/3 |  |  |  |  |

| `replay_matches?` | function | replay_matches?/3 |  |  |  |  |

| `sha256?` | function | sha256?/1 |  |  |  |  |

| `sha256_prefixed?` | function | sha256_prefixed?/1 |  |  |  |  |

| `standing` | function | standing/1 |  |  |  |  |

| `trigger_refusal` | function | trigger_refusal/3 |  |  |  |  |

| `validate_evaluation` | function | validate_evaluation/0 |  |  |  |  |

| `validate_evaluation` | function | validate_evaluation/3 |  |  |  |  |

| `validate_evaluation_receipt` | function | validate_evaluation_receipt/5 |  |  |  |  |

| `validate_evaluations` | function | validate_evaluations/2 |  |  |  |  |

| `validate_evaluations` | function | validate_evaluations/2 |  |  |  |  |

| `validate_external_trigger_link` | function | validate_external_trigger_link/4 |  |  |  |  |

| `validate_intent` | function | validate_intent/3 |  |  |  |  |

| `validate_intent` | function | validate_intent/0 |  |  |  |  |

| `validate_intent` | function | validate_intent/3 |  |  |  |  |

| `validate_observation` | function | validate_observation/2 |  |  |  |  |

| `validate_observation` | function | validate_observation/2 |  |  |  |  |

| `validate_observations` | function | validate_observations/1 |  |  |  |  |

| `validate_observations` | function | validate_observations/1 |  |  |  |  |

| `validate_options` | function | validate_options/1 |  |  |  |  |

| `validate_trigger_receipt` | function | validate_trigger_receipt/3 |  |  |  |  |

| `validate_trigger_receipt` | function | validate_trigger_receipt/3 |  |  |  |  |

| `validate_trigger_receipts` | function | validate_trigger_receipts/2 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |

| `args` | function | args/0 |  |  |  |  |

| `returns` | function | returns/0 |  |  |  |  |

| `args` | function | args/0 |  |  |  |  |

| `returns` | function | returns/0 |  |  |  |  |

| `args` | function | args/0 |  |  |  |  |

| `returns` | function | returns/0 |  |  |  |  |

| `change` | function | change/0 |  |  |  |  |

| `compile_api_bundle` | function | compile_api_bundle/2 |  |  |  |  |

| `compile_bundle` | function | compile_bundle/2 |  |  |  |  |

| `compile_jsonld_bundle` | function | compile_jsonld_bundle/2 |  |  |  |  |

| `compile_semantic_types_bundle` | function | compile_semantic_types_bundle/2 |  |  |  |  |

| `compile_turtle_bundle` | function | compile_turtle_bundle/2 |  |  |  |  |

| `encode_json` | function | encode_json/1 |  |  |  |  |

| `graphql_files` | function | graphql_files/2 |  |  |  |  |

| `json_key` | function | json_key/1 |  |  |  |  |

| `json_key` | function | json_key/1 |  |  |  |  |

| `json_key` | function | json_key/1 |  |  |  |  |

| `json_key` | function | json_key/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `verify_staged` | function | verify_staged/2 |  |  |  |  |

| `bundle` | function | bundle/1 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile_turtle` | function | compile_turtle/2 |  |  |  |  |

| `encode_json` | function | encode_json/1 |  |  |  |  |

| `json_key` | function | json_key/1 |  |  |  |  |

| `json_key` | function | json_key/1 |  |  |  |  |

| `json_key` | function | json_key/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `verify_staged` | function | verify_staged/2 |  |  |  |  |

| `bundle` | function | bundle/1 |  |  |  |  |

| `bundle` | function | bundle/1 |  |  |  |  |

| `datatype_range` | function | datatype_range/1 |  |  |  |  |

| `datatype_range` | function | datatype_range/1 |  |  |  |  |

| `emit` | function | emit/1 |  |  |  |  |

| `ontology` | function | ontology/1 |  |  |  |  |

| `relationship_statements` | function | relationship_statements/2 |  |  |  |  |

| `resource_key` | function | resource_key/1 |  |  |  |  |

| `resource_key` | function | resource_key/1 |  |  |  |  |

| `scalar_statements` | function | scalar_statements/1 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `target_classes` | function | target_classes/2 |  |  |  |  |

| `contract` | function | contract/1 |  |  |  |  |

| `contract` | function | contract/1 |  |  |  |  |

| `digest` | function | digest/1 |  |  |  |  |

| `validate_authority` | function | validate_authority/1 |  |  |  |  |

| `validate_authority` | function | validate_authority/1 |  |  |  |  |

| `validate_subject` | function | validate_subject/1 |  |  |  |  |

| `validate_subject` | function | validate_subject/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `digest` | function | digest/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `normalize` | function | normalize/1 |  |  |  |  |

| `normalize` | function | normalize/1 |  |  |  |  |

| `normalize` | function | normalize/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `digest` | function | digest/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `cleanup_preflight` | function | cleanup_preflight/1 |  |  |  |  |

| `setup_preflight` | function | setup_preflight/3 |  |  |  |  |

| `AshR2RML.GrandExample.Organization` | ash_resource |  |  |  |  |  |

| `AshR2RML.GrandExample.Person` | ash_resource |  |  |  |  |  |

| `AshR2RML.GrandExample.SemanticManifest` | ash_resource |  |  |  |  |  |

| `AshR2RML.GrandExample.Shipment` | ash_resource |  |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `dump_to_embedded` | function | dump_to_embedded/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `storage_type` | function | storage_type/1 |  |  |  |  |

| `to_rdf_lexical` | function | to_rdf_lexical/1 |  |  |  |  |

| `AshR2RML.GrandExample.Warehouse` | ash_resource |  |  |  |  |  |

| `with_audit_span` | function | with_audit_span/4 |  |  |  |  |

| `derived_queries` | function | derived_queries/1 |  |  |  |  |

| `domain` | function | domain/1 |  |  |  |  |

| `domain_enabled?` | function | domain_enabled?/1 |  |  |  |  |

| `domain_opt_enabled?` | function | domain_opt_enabled?/1 |  |  |  |  |

| `enabled?` | function | enabled?/1 |  |  |  |  |

| `resource_enabled?` | function | resource_enabled?/1 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `before?` | function | before?/1 |  |  |  |  |

| `before?` | function | before?/1 |  |  |  |  |

| `before?` | function | before?/1 |  |  |  |  |

| `before?` | function | before?/1 |  |  |  |  |

| `before?` | function | before?/1 |  |  |  |  |

| `derive_type` | function | derive_type/1 |  |  |  |  |

| `paginate_with` | function | paginate_with/1 |  |  |  |  |

| `paginate_with` | function | paginate_with/1 |  |  |  |  |

| `paginate_with` | function | paginate_with/1 |  |  |  |  |

| `paginate_with` | function | paginate_with/1 |  |  |  |  |

| `project` | function | project/1 |  |  |  |  |

| `queries_for` | function | queries_for/3 |  |  |  |  |

| `query` | function | query/1 |  |  |  |  |

| `read_actions` | function | read_actions/1 |  |  |  |  |

| `resource?` | function | resource?/1 |  |  |  |  |

| `transform` | function | transform/1 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |

| `AshR2RML.GraphqlAutoProjection.Drone` | ash_resource |  |  |  |  |  |

| `AshR2RML.GraphqlAutoProjection.Robot` | ash_resource |  |  |  |  |  |

| `AshR2RML.GraphqlProjection.Person` | ash_resource |  |  |  |  |  |

| `compile_turtle` | function | compile_turtle/2 |  |  |  |  |

| `from_graph` | function | from_graph/2 |  |  |  |  |

| `from_turtle` | function | from_turtle/2 |  |  |  |  |

| `identity_keys` | function | identity_keys/3 |  |  |  |  |

| `parse_identities` | function | parse_identities/3 |  |  |  |  |

| `parse_resource` | function | parse_resource/2 |  |  |  |  |

| `parse_resources` | function | parse_resources/2 |  |  |  |  |

| `binary_sha256` | function | binary_sha256/1 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `term` | function | term/1 |  |  |  |  |

| `term` | function | term/1 |  |  |  |  |

| `term` | function | term/1 |  |  |  |  |

| `term` | function | term/1 |  |  |  |  |

| `term` | function | term/1 |  |  |  |  |

| `column` | function | column/2 |  |  |  |  |

| `extract_identities` | function | extract_identities/2 |  |  |  |  |

| `identities` | function | identities/2 |  |  |  |  |

| `identities` | function | identities/2 |  |  |  |  |

| `identities` | function | identities/2 |  |  |  |  |

| `infer_logical_table` | function | infer_logical_table/1 |  |  |  |  |

| `infer_logical_table_from_data_layer` | function | infer_logical_table_from_data_layer/1 |  |  |  |  |

| `infer_postgres_table` | function | infer_postgres_table/1 |  |  |  |  |

| `logical_table` | function | logical_table/2 |  |  |  |  |

| `many_to_many_metadata` | function | many_to_many_metadata/2 |  |  |  |  |

| `persisted_logical_table` | function | persisted_logical_table/1 |  |  |  |  |

| `relationship` | function | relationship/2 |  |  |  |  |

| `relationship_metadata` | function | relationship_metadata/2 |  |  |  |  |

| `simple_relationship_metadata` | function | simple_relationship_metadata/2 |  |  |  |  |

| `stable_subject_identity?` | function | stable_subject_identity?/2 |  |  |  |  |

| `fetch_resource` | function | fetch_resource/2 |  |  |  |  |

| `generate` | function | generate/1 |  |  |  |  |

| `manifest_result` | function | manifest_result/1 |  |  |  |  |

| `resource_lookup` | function | resource_lookup/1 |  |  |  |  |

| `admit_contexts` | function | admit_contexts/2 |  |  |  |  |

| `compact` | function | compact/3 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `context_urls` | function | context_urls/1 |  |  |  |  |

| `context_urls` | function | context_urls/1 |  |  |  |  |

| `context_urls` | function | context_urls/1 |  |  |  |  |

| `decode_document` | function | decode_document/1 |  |  |  |  |

| `decode_document` | function | decode_document/1 |  |  |  |  |

| `decode_document` | function | decode_document/1 |  |  |  |  |

| `encode_rdf` | function | encode_rdf/2 |  |  |  |  |

| `expand` | function | expand/2 |  |  |  |  |

| `ingest` | function | ingest/2 |  |  |  |  |

| `json_options` | function | json_options/1 |  |  |  |  |

| `jsonld_error` | function | jsonld_error/2 |  |  |  |  |

| `maybe_compact` | function | maybe_compact/2 |  |  |  |  |

| `remote_contexts` | function | remote_contexts/1 |  |  |  |  |

| `remote_contexts` | function | remote_contexts/1 |  |  |  |  |

| `remote_contexts` | function | remote_contexts/1 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `to_rdf` | function | to_rdf/2 |  |  |  |  |

| `action_name` | function | action_name/1 |  |  |  |  |

| `action_name` | function | action_name/1 |  |  |  |  |

| `action_name` | function | action_name/1 |  |  |  |  |

| `action_type` | function | action_type/2 |  |  |  |  |

| `ash_pattern` | function | ash_pattern/1 |  |  |  |  |

| `ash_pattern` | function | ash_pattern/1 |  |  |  |  |

| `ash_source` | function | ash_source/1 |  |  |  |  |

| `ash_source` | function | ash_source/1 |  |  |  |  |

| `atomic_keys` | function | atomic_keys/1 |  |  |  |  |

| `atomic_keys` | function | atomic_keys/1 |  |  |  |  |

| `atomic_keys` | function | atomic_keys/1 |  |  |  |  |

| `attribute_delta` | function | attribute_delta/4 |  |  |  |  |

| `build_receipt` | function | build_receipt/2 |  |  |  |  |

| `canonical_pattern` | function | canonical_pattern/1 |  |  |  |  |

| `canonical_pattern` | function | canonical_pattern/1 |  |  |  |  |

| `canonical_pattern` | function | canonical_pattern/1 |  |  |  |  |

| `canonical_pattern` | function | canonical_pattern/1 |  |  |  |  |

| `changed_attribute_names` | function | changed_attribute_names/1 |  |  |  |  |

| `changed_relationship_names` | function | changed_relationship_names/1 |  |  |  |  |

| `evaluate` | function | evaluate/3 |  |  |  |  |

| `existing_atom_key` | function | existing_atom_key/2 |  |  |  |  |

| `explicit_trigger_receipt` | function | explicit_trigger_receipt/4 |  |  |  |  |

| `field_match?` | function | field_match?/3 |  |  |  |  |

| `field_match?` | function | field_match?/3 |  |  |  |  |

| `get` | function | get/3 |  |  |  |  |

| `inspect_type` | function | inspect_type/1 |  |  |  |  |

| `inspect_type` | function | inspect_type/1 |  |  |  |  |

| `key_string` | function | key_string/1 |  |  |  |  |

| `key_string` | function | key_string/1 |  |  |  |  |

| `key_string` | function | key_string/1 |  |  |  |  |

| `match_receipts` | function | match_receipts/3 |  |  |  |  |

| `matches?` | function | matches?/3 |  |  |  |  |

| `matches?` | function | matches?/3 |  |  |  |  |

| `module_name` | function | module_name/1 |  |  |  |  |

| `module_name` | function | module_name/1 |  |  |  |  |

| `module_name` | function | module_name/1 |  |  |  |  |

| `normalize_atomish` | function | normalize_atomish/1 |  |  |  |  |

| `normalize_atomish` | function | normalize_atomish/1 |  |  |  |  |

| `normalize_atomish` | function | normalize_atomish/1 |  |  |  |  |

| `normalize_atomish` | function | normalize_atomish/1 |  |  |  |  |

| `normalize_name` | function | normalize_name/1 |  |  |  |  |

| `normalize_name` | function | normalize_name/1 |  |  |  |  |

| `normalize_name` | function | normalize_name/1 |  |  |  |  |

| `normalize_name` | function | normalize_name/1 |  |  |  |  |

| `normalize_resource` | function | normalize_resource/1 |  |  |  |  |

| `normalize_resource` | function | normalize_resource/1 |  |  |  |  |

| `normalize_resource` | function | normalize_resource/1 |  |  |  |  |

| `observe` | function | observe/1 |  |  |  |  |

| `observe` | function | observe/1 |  |  |  |  |

| `observe` | function | observe/1 |  |  |  |  |

| `observe` | function | observe/1 |  |  |  |  |

| `observe` | function | observe/1 |  |  |  |  |

| `observe_many` | function | observe_many/1 |  |  |  |  |

| `observe_notification` | function | observe_notification/1 |  |  |  |  |

| `observe_notification` | function | observe_notification/1 |  |  |  |  |

| `observe_notification` | function | observe_notification/1 |  |  |  |  |

| `primary_key` | function | primary_key/2 |  |  |  |  |

| `primary_key` | function | primary_key/2 |  |  |  |  |

| `primary_key` | function | primary_key/2 |  |  |  |  |

| `projection` | function | projection/1 |  |  |  |  |

| `record_value` | function | record_value/2 |  |  |  |  |

| `record_value` | function | record_value/2 |  |  |  |  |

| `record_value` | function | record_value/2 |  |  |  |  |

| `refusal` | function | refusal/3 |  |  |  |  |

| `stable_scalar` | function | stable_scalar/1 |  |  |  |  |

| `stable_scalar` | function | stable_scalar/1 |  |  |  |  |

| `stable_scalar` | function | stable_scalar/1 |  |  |  |  |

| `stable_value` | function | stable_value/1 |  |  |  |  |

| `stable_value` | function | stable_value/1 |  |  |  |  |

| `stable_value` | function | stable_value/1 |  |  |  |  |

| `stable_value` | function | stable_value/1 |  |  |  |  |

| `stable_value` | function | stable_value/1 |  |  |  |  |

| `stable_value` | function | stable_value/1 |  |  |  |  |

| `stable_value` | function | stable_value/1 |  |  |  |  |

| `stable_value` | function | stable_value/1 |  |  |  |  |

| `stable_value` | function | stable_value/1 |  |  |  |  |

| `stable_value` | function | stable_value/1 |  |  |  |  |

| `subset_match?` | function | subset_match?/2 |  |  |  |  |

| `subset_match?` | function | subset_match?/2 |  |  |  |  |

| `transition_match` | function | transition_match/3 |  |  |  |  |

| `transition_match` | function | transition_match/3 |  |  |  |  |

| `trigger_receipts` | function | trigger_receipts/2 |  |  |  |  |

| `validate_pattern` | function | validate_pattern/3 |  |  |  |  |

| `validate_transition` | function | validate_transition/3 |  |  |  |  |

| `validate_transition` | function | validate_transition/3 |  |  |  |  |

| `validate_transition` | function | validate_transition/3 |  |  |  |  |

| `admit_rule` | function | admit_rule/1 |  |  |  |  |

| `admit_rule` | function | admit_rule/1 |  |  |  |  |

| `evaluate` | function | evaluate/3 |  |  |  |  |

| `evaluate` | function | evaluate/3 |  |  |  |  |

| `evaluate` | function | evaluate/3 |  |  |  |  |

| `parse_body` | function | parse_body/2 |  |  |  |  |

| `parse_head_vars` | function | parse_head_vars/2 |  |  |  |  |

| `split_rule` | function | split_rule/1 |  |  |  |  |

| `notify` | function | notify/1 |  |  |  |  |

| `safe_observe` | function | safe_observe/2 |  |  |  |  |

| `section` | function | section/0 |  |  |  |  |

| `hooks` | function | hooks/1 |  |  |  |  |

| `from_turtle` | function | from_turtle/2 |  |  |  |  |

| `from_notification` | function | from_notification/1 |  |  |  |  |

| `brce_request` | function | brce_request/2 |  |  |  |  |

| `candidate_boundary` | function | candidate_boundary/1 |  |  |  |  |

| `cognition_elimination_rate` | function | cognition_elimination_rate/2 |  |  |  |  |

| `cognition_elimination_rate` | function | cognition_elimination_rate/2 |  |  |  |  |

| `cognition_elimination_rate` | function | cognition_elimination_rate/2 |  |  |  |  |

| `evaluate` | function | evaluate/3 |  |  |  |  |

| `evaluate` | function | evaluate/3 |  |  |  |  |

| `evaluate` | function | evaluate/3 |  |  |  |  |

| `evidence_envelope` | function | evidence_envelope/2 |  |  |  |  |

| `evidence_identity` | function | evidence_identity/1 |  |  |  |  |

| `evidence_quality` | function | evidence_quality/1 |  |  |  |  |

| `minimum_evidence` | function | minimum_evidence/3 |  |  |  |  |

| `refusal` | function | refusal/3 |  |  |  |  |

| `from_graph` | function | from_graph/2 |  |  |  |  |

| `from_turtle` | function | from_turtle/2 |  |  |  |  |

| `native_hook_graph?` | function | native_hook_graph?/1 |  |  |  |  |

| `parse_hook` | function | parse_hook/2 |  |  |  |  |

| `require_construct_ceiling` | function | require_construct_ceiling/3 |  |  |  |  |

| `require_receipt_policy` | function | require_receipt_policy/3 |  |  |  |  |

| `admit_shapes_graph` | function | admit_shapes_graph/1 |  |  |  |  |

| `admit_shapes_graph` | function | admit_shapes_graph/1 |  |  |  |  |

| `admit_shapes_graph` | function | admit_shapes_graph/1 |  |  |  |  |

| `class_violations` | function | class_violations/6 |  |  |  |  |

| `class_violations` | function | class_violations/6 |  |  |  |  |

| `conforms` | function | conforms/3 |  |  |  |  |

| `conforms` | function | conforms/3 |  |  |  |  |

| `datatype_violations` | function | datatype_violations/5 |  |  |  |  |

| `datatype_violations` | function | datatype_violations/5 |  |  |  |  |

| `has_type?` | function | has_type?/3 |  |  |  |  |

| `index_statements` | function | index_statements/1 |  |  |  |  |

| `literal_datatype_matches?` | function | literal_datatype_matches?/2 |  |  |  |  |

| `literal_datatype_matches?` | function | literal_datatype_matches?/2 |  |  |  |  |

| `literal_datatype_matches?` | function | literal_datatype_matches?/2 |  |  |  |  |

| `literal_datatype_matches?` | function | literal_datatype_matches?/2 |  |  |  |  |

| `literal_datatype_matches?` | function | literal_datatype_matches?/2 |  |  |  |  |

| `max_count_violation` | function | max_count_violation/5 |  |  |  |  |

| `max_count_violation` | function | max_count_violation/5 |  |  |  |  |

| `min_count_violation` | function | min_count_violation/5 |  |  |  |  |

| `min_count_violation` | function | min_count_violation/5 |  |  |  |  |

| `objects` | function | objects/3 |  |  |  |  |

| `pattern_violations` | function | pattern_violations/5 |  |  |  |  |

| `pattern_violations` | function | pattern_violations/5 |  |  |  |  |

| `property_shapes` | function | property_shapes/2 |  |  |  |  |

| `property_violations` | function | property_violations/4 |  |  |  |  |

| `shapes_by_subject` | function | shapes_by_subject/1 |  |  |  |  |

| `single` | function | single/1 |  |  |  |  |

| `single` | function | single/1 |  |  |  |  |

| `statement3` | function | statement3/1 |  |  |  |  |

| `statement3` | function | statement3/1 |  |  |  |  |

| `targeted?` | function | targeted?/3 |  |  |  |  |

| `targeted?` | function | targeted?/3 |  |  |  |  |

| `term_string` | function | term_string/1 |  |  |  |  |

| `term_string` | function | term_string/1 |  |  |  |  |

| `term_value` | function | term_value/1 |  |  |  |  |

| `to_integer` | function | to_integer/1 |  |  |  |  |

| `to_integer` | function | to_integer/1 |  |  |  |  |

| `to_integer` | function | to_integer/1 |  |  |  |  |

| `violation` | function | violation/5 |  |  |  |  |

| `all_dependencies_exist` | function | all_dependencies_exist/2 |  |  |  |  |

| `do_schedule` | function | do_schedule/3 |  |  |  |  |

| `schedule` | function | schedule/1 |  |  |  |  |

| `unique_ids` | function | unique_ids/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical_predicate` | function | canonical_predicate/1 |  |  |  |  |

| `dependencies` | function | dependencies/1 |  |  |  |  |

| `from_definition` | function | from_definition/1 |  |  |  |  |

| `from_plan` | function | from_plan/1 |  |  |  |  |

| `observation_projection` | function | observation_projection/1 |  |  |  |  |

| `projection` | function | projection/1 |  |  |  |  |

| `provenance_value` | function | provenance_value/3 |  |  |  |  |

| `validate_dependencies` | function | validate_dependencies/2 |  |  |  |  |

| `ash_action` | function | ash_action/3 |  |  |  |  |

| `from_intent` | function | from_intent/1 |  |  |  |  |

| `inert?` | function | inert?/1 |  |  |  |  |

| `inert?` | function | inert?/1 |  |  |  |  |

| `inert?` | function | inert?/1 |  |  |  |  |

| `inert?` | function | inert?/1 |  |  |  |  |

| `inert?` | function | inert?/1 |  |  |  |  |

| `inert?` | function | inert?/1 |  |  |  |  |

| `new` | function | new/4 |  |  |  |  |

| `normalize_kind` | function | normalize_kind/1 |  |  |  |  |

| `normalize_kind` | function | normalize_kind/1 |  |  |  |  |

| `normalize_kind` | function | normalize_kind/1 |  |  |  |  |

| `normalize_kind` | function | normalize_kind/1 |  |  |  |  |

| `normalize_kind` | function | normalize_kind/1 |  |  |  |  |

| `normalize_kind` | function | normalize_kind/1 |  |  |  |  |

| `normalize_kind` | function | normalize_kind/1 |  |  |  |  |

| `normalize_kind` | function | normalize_kind/1 |  |  |  |  |

| `normalize_kind` | function | normalize_kind/1 |  |  |  |  |

| `oban` | function | oban/3 |  |  |  |  |

| `projection` | function | projection/1 |  |  |  |  |

| `reactor` | function | reactor/2 |  |  |  |  |

| `require_unauthorized` | function | require_unauthorized/1 |  |  |  |  |

| `require_unauthorized` | function | require_unauthorized/1 |  |  |  |  |

| `stable_name` | function | stable_name/1 |  |  |  |  |

| `stable_name` | function | stable_name/1 |  |  |  |  |

| `stable_name` | function | stable_name/1 |  |  |  |  |

| `state_transition` | function | state_transition/3 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `before?` | function | before?/1 |  |  |  |  |

| `transform` | function | transform/1 |  |  |  |  |

| `AshR2RML.KnowledgeHookDslSectionSharing.ResourceExtWidget` | ash_resource |  |  |  |  |  |

| `admit` | function | admit/2 |  |  |  |  |

| `admit` | function | admit/2 |  |  |  |  |

| `admit` | function | admit/2 |  |  |  |  |

| `ambient_actuation?` | function | ambient_actuation?/1 |  |  |  |  |

| `ambiguous_property` | function | ambiguous_property/3 |  |  |  |  |

| `boolean_result` | function | boolean_result/2 |  |  |  |  |

| `boolean_result` | function | boolean_result/2 |  |  |  |  |

| `bound_result` | function | bound_result/4 |  |  |  |  |

| `bound_result` | function | bound_result/4 |  |  |  |  |

| `bound_result` | function | bound_result/4 |  |  |  |  |

| `bound_result` | function | bound_result/4 |  |  |  |  |

| `build_evaluation` | function | build_evaluation/5 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical_definition` | function | canonical_definition/1 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `construct_intent` | function | construct_intent/2 |  |  |  |  |

| `current_opts` | function | current_opts/1 |  |  |  |  |

| `evaluate` | function | evaluate/2 |  |  |  |  |

| `evaluate_hook` | function | evaluate_hook/3 |  |  |  |  |

| `evaluate_hook` | function | evaluate_hook/0 |  |  |  |  |

| `evaluate_hook` | function | evaluate_hook/0 |  |  |  |  |

| `evaluate_hook` | function | evaluate_hook/3 |  |  |  |  |

| `evaluate_hook` | function | evaluate_hook/3 |  |  |  |  |

| `evaluate_hook` | function | evaluate_hook/0 |  |  |  |  |

| `evaluate_hook` | function | evaluate_hook/0 |  |  |  |  |

| `evaluation_steps` | function | evaluation_steps/2 |  |  |  |  |

| `evaluation_steps` | function | evaluation_steps/2 |  |  |  |  |

| `evaluation_steps` | function | evaluation_steps/2 |  |  |  |  |

| `evaluation_steps` | function | evaluation_steps/2 |  |  |  |  |

| `evaluation_steps` | function | evaluation_steps/2 |  |  |  |  |

| `evaluation_steps` | function | evaluation_steps/2 |  |  |  |  |

| `evaluation_steps` | function | evaluation_steps/2 |  |  |  |  |

| `evaluation_steps` | function | evaluation_steps/2 |  |  |  |  |

| `execute_query` | function | execute_query/2 |  |  |  |  |

| `external_trigger_witness` | function | external_trigger_witness/2 |  |  |  |  |

| `extract_time_field_values` | function | extract_time_field_values/3 |  |  |  |  |

| `fetch_evaluated_at` | function | fetch_evaluated_at/2 |  |  |  |  |

| `from_graph` | function | from_graph/2 |  |  |  |  |

| `from_turtle` | function | from_turtle/2 |  |  |  |  |

| `get` | function | get/3 |  |  |  |  |

| `graph_sha256` | function | graph_sha256/1 |  |  |  |  |

| `index_statements` | function | index_statements/1 |  |  |  |  |

| `inert_term?` | function | inert_term?/1 |  |  |  |  |

| `inert_term?` | function | inert_term?/1 |  |  |  |  |

| `inert_term?` | function | inert_term?/1 |  |  |  |  |

| `inert_term?` | function | inert_term?/1 |  |  |  |  |

| `inert_term?` | function | inert_term?/1 |  |  |  |  |

| `inert_term?` | function | inert_term?/1 |  |  |  |  |

| `missing_property` | function | missing_property/2 |  |  |  |  |

| `normalize_bound_predicate` | function | normalize_bound_predicate/4 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_comparator` | function | normalize_comparator/1 |  |  |  |  |

| `normalize_datalog_predicate` | function | normalize_datalog_predicate/2 |  |  |  |  |

| `normalize_definition` | function | normalize_definition/1 |  |  |  |  |

| `normalize_definition` | function | normalize_definition/1 |  |  |  |  |

| `normalize_definitions` | function | normalize_definitions/1 |  |  |  |  |

| `normalize_intent` | function | normalize_intent/2 |  |  |  |  |

| `normalize_intent` | function | normalize_intent/2 |  |  |  |  |

| `normalize_intent` | function | normalize_intent/2 |  |  |  |  |

| `normalize_intent` | function | normalize_intent/2 |  |  |  |  |

| `normalize_predicate` | function | normalize_predicate/3 |  |  |  |  |

| `normalize_predicate` | function | normalize_predicate/3 |  |  |  |  |

| `normalize_predicate` | function | normalize_predicate/3 |  |  |  |  |

| `normalize_predicate` | function | normalize_predicate/3 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_predicate_type` | function | normalize_predicate_type/1 |  |  |  |  |

| `normalize_shacl_focus` | function | normalize_shacl_focus/2 |  |  |  |  |

| `normalize_shacl_focus` | function | normalize_shacl_focus/2 |  |  |  |  |

| `normalize_shacl_focus` | function | normalize_shacl_focus/2 |  |  |  |  |

| `normalize_shacl_predicate` | function | normalize_shacl_predicate/2 |  |  |  |  |

| `normalize_temporal_window_predicate` | function | normalize_temporal_window_predicate/3 |  |  |  |  |

| `normalize_trigger_type` | function | normalize_trigger_type/1 |  |  |  |  |

| `normalize_trigger_type` | function | normalize_trigger_type/1 |  |  |  |  |

| `normalize_trigger_type` | function | normalize_trigger_type/1 |  |  |  |  |

| `normalize_trigger_type` | function | normalize_trigger_type/1 |  |  |  |  |

| `normalize_trigger_type` | function | normalize_trigger_type/1 |  |  |  |  |

| `normalize_trigger_type` | function | normalize_trigger_type/1 |  |  |  |  |

| `normalize_trigger_type` | function | normalize_trigger_type/1 |  |  |  |  |

| `normalize_trigger_type` | function | normalize_trigger_type/1 |  |  |  |  |

| `normalize_trigger_type` | function | normalize_trigger_type/1 |  |  |  |  |

| `normalize_trigger_type` | function | normalize_trigger_type/1 |  |  |  |  |

| `objects` | function | objects/3 |  |  |  |  |

| `optional_literal` | function | optional_literal/3 |  |  |  |  |

| `optional_value` | function | optional_value/3 |  |  |  |  |

| `parse_gitvan_hook` | function | parse_gitvan_hook/2 |  |  |  |  |

| `parse_knhk_hook` | function | parse_knhk_hook/2 |  |  |  |  |

| `parse_many` | function | parse_many/2 |  |  |  |  |

| `parse_numeric` | function | parse_numeric/2 |  |  |  |  |

| `parse_xsd_datetime` | function | parse_xsd_datetime/1 |  |  |  |  |

| `parse_xsd_datetime` | function | parse_xsd_datetime/1 |  |  |  |  |

| `parse_xsd_datetime` | function | parse_xsd_datetime/1 |  |  |  |  |

| `present_ambient_keys` | function | present_ambient_keys/1 |  |  |  |  |

| `previous_opts` | function | previous_opts/1 |  |  |  |  |

| `projection` | function | projection/1 |  |  |  |  |

| `projection_definition` | function | projection_definition/1 |  |  |  |  |

| `require_knhk_receipt` | function | require_knhk_receipt/3 |  |  |  |  |

| `required_literal` | function | required_literal/4 |  |  |  |  |

| `required_object` | function | required_object/4 |  |  |  |  |

| `shacl_data` | function | shacl_data/1 |  |  |  |  |

| `statement3` | function | statement3/1 |  |  |  |  |

| `statement3` | function | statement3/1 |  |  |  |  |

| `subjects_of_type` | function | subjects_of_type/2 |  |  |  |  |

| `supported_gitvan_predicate` | function | supported_gitvan_predicate/3 |  |  |  |  |

| `temporal_window_result` | function | temporal_window_result/4 |  |  |  |  |

| `temporal_window_result` | function | temporal_window_result/4 |  |  |  |  |

| `temporal_window_result` | function | temporal_window_result/4 |  |  |  |  |

| `term_string` | function | term_string/1 |  |  |  |  |

| `term_value` | function | term_value/1 |  |  |  |  |

| `threshold_value` | function | threshold_value/3 |  |  |  |  |

| `threshold_value` | function | threshold_value/3 |  |  |  |  |

| `threshold_value` | function | threshold_value/3 |  |  |  |  |

| `threshold_value_error` | function | threshold_value_error/2 |  |  |  |  |

| `unique_ids` | function | unique_ids/1 |  |  |  |  |

| `verify_bound` | function | verify_bound/4 |  |  |  |  |

| `verify_bound` | function | verify_bound/4 |  |  |  |  |

| `verify_bound` | function | verify_bound/4 |  |  |  |  |

| `verify_query_form` | function | verify_query_form/3 |  |  |  |  |

| `verify_query_form` | function | verify_query_form/3 |  |  |  |  |

| `verify_query_form` | function | verify_query_form/3 |  |  |  |  |

| `verify_query_form` | function | verify_query_form/3 |  |  |  |  |

| `verify_temporal_comparator` | function | verify_temporal_comparator/2 |  |  |  |  |

| `verify_temporal_unit` | function | verify_temporal_unit/2 |  |  |  |  |

| `verify_temporal_unit` | function | verify_temporal_unit/2 |  |  |  |  |

| `verify_time_field` | function | verify_time_field/2 |  |  |  |  |

| `verify_time_field` | function | verify_time_field/2 |  |  |  |  |

| `verify_time_field` | function | verify_time_field/2 |  |  |  |  |

| `verify_window` | function | verify_window/2 |  |  |  |  |

| `verify_window` | function | verify_window/2 |  |  |  |  |

| `observe` | function | observe/1 |  |  |  |  |

| `AshR2RML.KnowledgeHooks.RaisingWidget` | ash_resource |  |  |  |  |  |

| `clear` | function | clear/0 |  |  |  |  |

| `observations` | function | observations/1 |  |  |  |  |

| `record` | function | record/1 |  |  |  |  |

| `start` | function | start/0 |  |  |  |  |

| `observe` | function | observe/1 |  |  |  |  |

| `AshR2RML.KnowledgeHooks.Widget` | ash_resource |  |  |  |  |  |

| `evaluate_cells` | function | evaluate_cells/2 |  |  |  |  |

| `extract_cells` | function | extract_cells/1 |  |  |  |  |

| `run` | function | run/1 |  |  |  |  |

| `plan` | function | plan/2 |  |  |  |  |

| `verify_staged` | function | verify_staged/2 |  |  |  |  |

| `mapping_identity` | function | mapping_identity/1 |  |  |  |  |

| `normalize` | function | normalize/1 |  |  |  |  |

| `normalize` | function | normalize/1 |  |  |  |  |

| `normalize_object_map` | function | normalize_object_map/1 |  |  |  |  |

| `normalize_predicate_object_map` | function | normalize_predicate_object_map/1 |  |  |  |  |

| `normalize_reference_object_map` | function | normalize_reference_object_map/1 |  |  |  |  |

| `normalize_subject_map` | function | normalize_subject_map/1 |  |  |  |  |

| `sort_graph_maps` | function | sort_graph_maps/1 |  |  |  |  |

| `stable_subject_identity?` | function | stable_subject_identity?/1 |  |  |  |  |

| `stable_subject_identity?` | function | stable_subject_identity?/1 |  |  |  |  |

| `stable_subject_identity?` | function | stable_subject_identity?/1 |  |  |  |  |

| `subject_identity_columns` | function | subject_identity_columns/1 |  |  |  |  |

| `subject_identity_columns` | function | subject_identity_columns/1 |  |  |  |  |

| `subject_identity_columns` | function | subject_identity_columns/1 |  |  |  |  |

| `template_fields` | function | template_fields/1 |  |  |  |  |

| `template_fields` | function | template_fields/1 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |

| `validate_classes` | function | validate_classes/1 |  |  |  |  |

| `validate_logical_table` | function | validate_logical_table/1 |  |  |  |  |

| `validate_logical_table` | function | validate_logical_table/1 |  |  |  |  |

| `validate_properties` | function | validate_properties/1 |  |  |  |  |

| `validate_subject` | function | validate_subject/1 |  |  |  |  |

| `validate_subject` | function | validate_subject/1 |  |  |  |  |

| `validate_subject_columns` | function | validate_subject_columns/2 |  |  |  |  |

| `validate_subject_columns` | function | validate_subject_columns/2 |  |  |  |  |

| `validate_subject_columns` | function | validate_subject_columns/2 |  |  |  |  |

| `action_fields` | function | action_fields/0 |  |  |  |  |

| `diff` | function | diff/2 |  |  |  |  |

| `empty?` | function | empty?/1 |  |  |  |  |

| `fetch_graph` | function | fetch_graph/2 |  |  |  |  |

| `get` | function | get/2 |  |  |  |  |

| `get` | function | get/2 |  |  |  |  |

| `inserts` | function | inserts/1 |  |  |  |  |

| `invert` | function | invert/1 |  |  |  |  |

| `merged_graph` | function | merged_graph/1 |  |  |  |  |

| `new` | function | new/1 |  |  |  |  |

| `removals` | function | removals/1 |  |  |  |  |

| `removals` | function | removals/1 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |

| `validate_no_add_remove_overlap` | function | validate_no_add_remove_overlap/1 |  |  |  |  |

| `validate_no_add_remove_overlap` | function | validate_no_add_remove_overlap/1 |  |  |  |  |

| `validate_no_add_remove_overlap` | function | validate_no_add_remove_overlap/1 |  |  |  |  |

| `validate_no_update_replace_overlap` | function | validate_no_update_replace_overlap/1 |  |  |  |  |

| `validate_no_update_replace_overlap` | function | validate_no_update_replace_overlap/1 |  |  |  |  |

| `validate_no_update_replace_overlap` | function | validate_no_update_replace_overlap/1 |  |  |  |  |

| `ash_fields` | function | ash_fields/1 |  |  |  |  |

| `ash_fields` | function | ash_fields/1 |  |  |  |  |

| `attach_generated_at_time` | function | attach_generated_at_time/2 |  |  |  |  |

| `attach_generated_at_time` | function | attach_generated_at_time/3 |  |  |  |  |

| `attach_was_derived_from` | function | attach_was_derived_from/2 |  |  |  |  |

| `available_fields` | function | available_fields/1 |  |  |  |  |

| `get` | function | get/2 |  |  |  |  |

| `get` | function | get/2 |  |  |  |  |

| `pom_matches_field?` | function | pom_matches_field?/2 |  |  |  |  |

| `project` | function | project/2 |  |  |  |  |

| `project` | function | project/2 |  |  |  |  |

| `project` | function | project/2 |  |  |  |  |

| `put_predicate` | function | put_predicate/2 |  |  |  |  |

| `source_datatype` | function | source_datatype/2 |  |  |  |  |

| `source_datatype_from_ash` | function | source_datatype_from_ash/2 |  |  |  |  |

| `source_datatype_from_ash` | function | source_datatype_from_ash/2 |  |  |  |  |

| `validate_generated_at` | function | validate_generated_at/2 |  |  |  |  |

| `validate_generated_at` | function | validate_generated_at/2 |  |  |  |  |

| `validate_generated_at` | function | validate_generated_at/2 |  |  |  |  |

| `validate_template` | function | validate_template/2 |  |  |  |  |

| `validate_template` | function | validate_template/2 |  |  |  |  |

| `validate_template` | function | validate_template/2 |  |  |  |  |

| `parse_excluded_tags` | function | parse_excluded_tags/1 |  |  |  |  |

| `parse_exit_status` | function | parse_exit_status/1 |  |  |  |  |

| `parse_test_summary` | function | parse_test_summary/1 |  |  |  |  |

| `parse_timestamp` | function | parse_timestamp/1 |  |  |  |  |

| `reconcile_exclusion_claim` | function | reconcile_exclusion_claim/2 |  |  |  |  |

| `validate` | function | validate/2 |  |  |  |  |

| `validate_freshness` | function | validate_freshness/2 |  |  |  |  |

| `validate_freshness` | function | validate_freshness/2 |  |  |  |  |

| `format_refusals` | function | format_refusals/1 |  |  |  |  |

| `json_key` | function | json_key/1 |  |  |  |  |

| `json_key` | function | json_key/1 |  |  |  |  |

| `json_key` | function | json_key/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `json_term` | function | json_term/1 |  |  |  |  |

| `load_json` | function | load_json/1 |  |  |  |  |

| `load_source` | function | load_source/1 |  |  |  |  |

| `load_source` | function | load_source/1 |  |  |  |  |

| `plan!` | function | plan!/1 |  |  |  |  |

| `print_json` | function | print_json/1 |  |  |  |  |

| `dispatch` | function | dispatch/3 |  |  |  |  |

| `engine_name` | function | engine_name/0 |  |  |  |  |

| `query` | function | query/3 |  |  |  |  |

| `query` | function | query/3 |  |  |  |  |

| `engine_name` | function | engine_name/0 |  |  |  |  |

| `query` | function | query/3 |  |  |  |  |

| `admit` | function | admit/3 |  |  |  |  |

| `mark_executed` | function | mark_executed/1 |  |  |  |  |

| `ontop_supported` | function | ontop_supported/1 |  |  |  |  |

| `query_supported` | function | query_supported/1 |  |  |  |  |

| `query_supported` | function | query_supported/1 |  |  |  |  |

| `seal` | function | seal/1 |  |  |  |  |

| `seal` | function | seal/1 |  |  |  |  |

| `supported` | function | supported/2 |  |  |  |  |

| `supported` | function | supported/2 |  |  |  |  |

| `supported` | function | supported/2 |  |  |  |  |

| `materialize` | function | materialize/3 |  |  |  |  |

| `materialize_many` | function | materialize_many/2 |  |  |  |  |

| `append_option` | function | append_option/3 |  |  |  |  |

| `append_option` | function | append_option/3 |  |  |  |  |

| `append_option` | function | append_option/3 |  |  |  |  |

| `bounded_failure` | function | bounded_failure/0 |  |  |  |  |

| `bounded_integer` | function | bounded_integer/2 |  |  |  |  |

| `bounded_integer` | function | bounded_integer/2 |  |  |  |  |

| `command` | function | command/1 |  |  |  |  |

| `csv_field` | function | csv_field/1 |  |  |  |  |

| `elapsed` | function | elapsed/1 |  |  |  |  |

| `execute` | function | execute/3 |  |  |  |  |

| `execution_failure` | function | execution_failure/0 |  |  |  |  |

| `finish_csv` | function | finish_csv/3 |  |  |  |  |

| `finish_csv` | function | finish_csv/3 |  |  |  |  |

| `get` | function | get/3 |  |  |  |  |

| `get` | function | get/3 |  |  |  |  |

| `get` | function | get/3 |  |  |  |  |

| `hash_file_or_value` | function | hash_file_or_value/2 |  |  |  |  |

| `hash_file_or_value` | function | hash_file_or_value/2 |  |  |  |  |

| `hash_file_or_value` | function | hash_file_or_value/2 |  |  |  |  |

| `observation_hash` | function | observation_hash/1 |  |  |  |  |

| `parse_csv` | function | parse_csv/1 |  |  |  |  |

| `parse_csv_chars` | function | parse_csv_chars/5 |  |  |  |  |

| `parse_csv_chars` | function | parse_csv_chars/5 |  |  |  |  |

| `parse_csv_chars` | function | parse_csv_chars/5 |  |  |  |  |

| `parse_csv_chars` | function | parse_csv_chars/5 |  |  |  |  |

| `parse_csv_chars` | function | parse_csv_chars/5 |  |  |  |  |

| `parse_csv_chars` | function | parse_csv_chars/5 |  |  |  |  |

| `parse_csv_chars` | function | parse_csv_chars/5 |  |  |  |  |

| `parse_csv_chars` | function | parse_csv_chars/5 |  |  |  |  |

| `query` | function | query/1 |  |  |  |  |

| `query` | function | query/2 |  |  |  |  |

| `redact` | function | redact/1 |  |  |  |  |

| `redact` | function | redact/2 |  |  |  |  |

| `redact` | function | redact/2 |  |  |  |  |

| `redact` | function | redact/2 |  |  |  |  |

| `required` | function | required/2 |  |  |  |  |

| `retained_output` | function | retained_output/2 |  |  |  |  |

| `run_bounded` | function | run_bounded/4 |  |  |  |  |

| `runner_failure` | function | runner_failure/0 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `strip_ontop_log_noise` | function | strip_ontop_log_noise/1 |  |  |  |  |

| `counts` | function | counts/1 |  |  |  |  |

| `counts` | function | counts/1 |  |  |  |  |

| `feature_status` | function | feature_status/2 |  |  |  |  |

| `feature_status` | function | feature_status/2 |  |  |  |  |

| `feature_status` | function | feature_status/2 |  |  |  |  |

| `feature_status` | function | feature_status/2 |  |  |  |  |

| `feature_status` | function | feature_status/2 |  |  |  |  |

| `feature_status` | function | feature_status/2 |  |  |  |  |

| `feature_status` | function | feature_status/2 |  |  |  |  |

| `member_status` | function | member_status/2 |  |  |  |  |

| `probe` | function | probe/3 |  |  |  |  |

| `profile` | function | profile/0 |  |  |  |  |

| `protocol_probes` | function | protocol_probes/0 |  |  |  |  |

| `refusal_code` | function | refusal_code/1 |  |  |  |  |

| `refusal_code` | function | refusal_code/1 |  |  |  |  |

| `require_supported` | function | require_supported/2 |  |  |  |  |

| `section_counts` | function | section_counts/1 |  |  |  |  |

| `section_feature_status` | function | section_feature_status/2 |  |  |  |  |

| `sections` | function | sections/1 |  |  |  |  |

| `source_identity` | function | source_identity/0 |  |  |  |  |

| `standard` | function | standard/1 |  |  |  |  |

| `unknown_standard` | function | unknown_standard/1 |  |  |  |  |

| `unprobed` | function | unprobed/1 |  |  |  |  |

| `unprobed_supported_sections` | function | unprobed_supported_sections/1 |  |  |  |  |

| `unprobed_supported_sections` | function | unprobed_supported_sections/1 |  |  |  |  |

| `version` | function | version/0 |  |  |  |  |

| `AshR2RML.POWL.Ash.DecomposedNode` | ash_resource |  |  |  |  |  |

| `AshR2RML.POWL.Ash.FlowArc` | ash_resource |  |  |  |  |  |

| `AshR2RML.POWL.Ash.Place` | ash_resource |  |  |  |  |  |

| `AshR2RML.POWL.Ash.ProcessModel` | ash_resource |  |  |  |  |  |

| `AshR2RML.POWL.Ash.Transition` | ash_resource |  |  |  |  |  |

| `seed_retailer_process!` | function | seed_retailer_process!/0 |  |  |  |  |

| `new` | function | new/6 |  |  |  |  |

| `AshR2RML.PalantirMigrationFixture.Asset` | ash_resource |  |  |  |  |  |

| `AshR2RML.PalantirMigrationFixture.Organization` | ash_resource |  |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `compare` | function | compare/5 |  |  |  |  |

| `default_left` | function | default_left/1 |  |  |  |  |

| `default_right` | function | default_right/1 |  |  |  |  |

| `get` | function | get/2 |  |  |  |  |

| `normalize_multiset` | function | normalize_multiset/1 |  |  |  |  |

| `present_hash?` | function | present_hash?/1 |  |  |  |  |

| `query_hash` | function | query_hash/1 |  |  |  |  |

| `query_hash` | function | query_hash/1 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `__ash_r2rml_mapping__` | function | __ash_r2rml_mapping__/0 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `column_for_attribute` | function | column_for_attribute/2 |  |  |  |  |

| `column_for_attribute` | function | column_for_attribute/2 |  |  |  |  |

| `transform` | function | transform/1 |  |  |  |  |

| `filter_for_actor` | function | filter_for_actor/3 |  |  |  |  |

| `filter_for_actor` | function | filter_for_actor/3 |  |  |  |  |

| `evidence_identity` | function | evidence_identity/1 |  |  |  |  |

| `fetch` | function | fetch/3 |  |  |  |  |

| `normalize_evidence` | function | normalize_evidence/1 |  |  |  |  |

| `normalize_evidence` | function | normalize_evidence/1 |  |  |  |  |

| `present?` | function | present?/1 |  |  |  |  |

| `refusal` | function | refusal/4 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `standing` | function | standing/1 |  |  |  |  |

| `standing` | function | standing/1 |  |  |  |  |

| `standing` | function | standing/1 |  |  |  |  |

| `valid_evidence?` | function | valid_evidence?/2 |  |  |  |  |

| `contract` | function | contract/2 |  |  |  |  |

| `validate_labels` | function | validate_labels/1 |  |  |  |  |

| `admit` | function | admit/2 |  |  |  |  |

| `contract` | function | contract/1 |  |  |  |  |

| `stages` | function | stages/1 |  |  |  |  |

| `stages` | function | stages/1 |  |  |  |  |

| `stages` | function | stages/1 |  |  |  |  |

| `stages` | function | stages/1 |  |  |  |  |

| `contract` | function | contract/2 |  |  |  |  |

| `burn_status` | function | burn_status/1 |  |  |  |  |

| `burn_status` | function | burn_status/1 |  |  |  |  |

| `burn_status` | function | burn_status/1 |  |  |  |  |

| `burn_status` | function | burn_status/1 |  |  |  |  |

| `capacity` | function | capacity/2 |  |  |  |  |

| `ceil_div` | function | ceil_div/2 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `error_budget` | function | error_budget/2 |  |  |  |  |

| `evaluate` | function | evaluate/2 |  |  |  |  |

| `fetch` | function | fetch/3 |  |  |  |  |

| `number` | function | number/3 |  |  |  |  |

| `target_for` | function | target_for/2 |  |  |  |  |

| `target_for` | function | target_for/2 |  |  |  |  |

| `contract` | function | contract/1 |  |  |  |  |

| `fetch` | function | fetch/3 |  |  |  |  |

| `new` | function | new/1 |  |  |  |  |

| `present?` | function | present?/1 |  |  |  |  |

| `refusal` | function | refusal/2 |  |  |  |  |

| `achieved?` | function | achieved?/2 |  |  |  |  |

| `add` | function | add/2 |  |  |  |  |

| `add` | function | add/2 |  |  |  |  |

| `classes` | function | classes/0 |  |  |  |  |

| `highest` | function | highest/1 |  |  |  |  |

| `render` | function | render/1 |  |  |  |  |

| `render` | function | render/1 |  |  |  |  |

| `render` | function | render/1 |  |  |  |  |

| `render_bundle` | function | render_bundle/1 |  |  |  |  |

| `equivalent?` | function | equivalent?/2 |  |  |  |  |

| `graph_add` | function | graph_add/2 |  |  |  |  |

| `graph_add` | function | graph_add/2 |  |  |  |  |

| `graph_cleanup` | function | graph_cleanup/1 |  |  |  |  |

| `graph_delete` | function | graph_delete/2 |  |  |  |  |

| `graph_delete` | function | graph_delete/2 |  |  |  |  |

| `graph_intersection` | function | graph_intersection/2 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `complete` | function | complete/2 |  |  |  |  |

| `elapsed` | function | elapsed/2 |  |  |  |  |

| `error` | function | error/2 |  |  |  |  |

| `event` | function | event/3 |  |  |  |  |

| `event` | function | event/3 |  |  |  |  |

| `event` | function | event/3 |  |  |  |  |

| `evidence_result` | function | evidence_result/1 |  |  |  |  |

| `evidence_result` | function | evidence_result/1 |  |  |  |  |

| `init` | function | init/1 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `lookup_override` | function | lookup_override/2 |  |  |  |  |

| `provenance_from_metadata` | function | provenance_from_metadata/1 |  |  |  |  |

| `provenance_from_metadata` | function | provenance_from_metadata/1 |  |  |  |  |

| `resource_config` | function | resource_config/2 |  |  |  |  |

| `resource_config` | function | resource_config/2 |  |  |  |  |

| `resource_config` | function | resource_config/2 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `compensate` | function | compensate/4 |  |  |  |  |

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `compensate` | function | compensate/4 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `new` | function | new/4 |  |  |  |  |

| `convert_legacy` | function | convert_legacy/2 |  |  |  |  |

| `safe_spark_opt` | function | safe_spark_opt/3 |  |  |  |  |

| `section` | function | section/0 |  |  |  |  |

| `spark_resource?` | function | spark_resource?/1 |  |  |  |  |

| `mapped?` | function | mapped?/1 |  |  |  |  |

| `mapping` | function | mapping/1 |  |  |  |  |

| `mapping!` | function | mapping!/1 |  |  |  |  |

| `mapping_result` | function | mapping_result/1 |  |  |  |  |

| `sparql_queries` | function | sparql_queries/1 |  |  |  |  |

| `convert` | function | convert/1 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `after?` | function | after?/1 |  |  |  |  |

| `compile_dsl_relationship` | function | compile_dsl_relationship/3 |  |  |  |  |

| `compile_graphs` | function | compile_graphs/2 |  |  |  |  |

| `compile_object_map` | function | compile_object_map/3 |  |  |  |  |

| `compile_properties` | function | compile_properties/3 |  |  |  |  |

| `compile_property` | function | compile_property/3 |  |  |  |  |

| `compile_references` | function | compile_references/3 |  |  |  |  |

| `compile_subject` | function | compile_subject/3 |  |  |  |  |

| `compile_subject` | function | compile_subject/3 |  |  |  |  |

| `find_dsl_attribute` | function | find_dsl_attribute/2 |  |  |  |  |

| `reverse_ok` | function | reverse_ok/1 |  |  |  |  |

| `reverse_ok` | function | reverse_ok/1 |  |  |  |  |

| `transform` | function | transform/1 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |

| `render` | function | render/1 |  |  |  |  |

| `render` | function | render/1 |  |  |  |  |

| `build_plan` | function | build_plan/3 |  |  |  |  |

| `build_plan` | function | build_plan/3 |  |  |  |  |

| `execute` | function | execute/1 |  |  |  |  |

| `execute` | function | execute/1 |  |  |  |  |

| `execute` | function | execute/1 |  |  |  |  |

| `execute` | function | execute/1 |  |  |  |  |

| `execute` | function | execute/1 |  |  |  |  |

| `explore` | function | explore/2 |  |  |  |  |

| `maybe_candidate` | function | maybe_candidate/3 |  |  |  |  |

| `maybe_candidate` | function | maybe_candidate/3 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `common_query_identity` | function | common_query_identity/1 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `compare` | function | compare/3 |  |  |  |  |

| `require_observations` | function | require_observations/1 |  |  |  |  |

| `require_observations` | function | require_observations/1 |  |  |  |  |

| `require_observed` | function | require_observed/1 |  |  |  |  |

| `require_strategies` | function | require_strategies/2 |  |  |  |  |

| `unique_strategies` | function | unique_strategies/1 |  |  |  |  |

| `normalize_local_result` | function | normalize_local_result/2 |  |  |  |  |

| `normalize_local_result` | function | normalize_local_result/2 |  |  |  |  |

| `query` | function | query/2 |  |  |  |  |

| `do_query` | function | do_query/6 |  |  |  |  |

| `query` | function | query/3 |  |  |  |  |

| `query_with` | function | query_with/4 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/2 |  |  |  |  |

| `load_file` | function | load_file/2 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `hash_rows` | function | hash_rows/1 |  |  |  |  |

| `normalize` | function | normalize/1 |  |  |  |  |

| `normalize` | function | normalize/1 |  |  |  |  |

| `normalize` | function | normalize/1 |  |  |  |  |

| `normalize_binding` | function | normalize_binding/1 |  |  |  |  |

| `normalize_rdf_value` | function | normalize_rdf_value/1 |  |  |  |  |

| `normalize_statement` | function | normalize_statement/1 |  |  |  |  |

| `normalize_statement` | function | normalize_statement/1 |  |  |  |  |

| `normalize_term` | function | normalize_term/1 |  |  |  |  |

| `normalize_term` | function | normalize_term/1 |  |  |  |  |

| `normalize_term` | function | normalize_term/1 |  |  |  |  |

| `normalize_var_name` | function | normalize_var_name/1 |  |  |  |  |

| `normalize_var_name` | function | normalize_var_name/1 |  |  |  |  |

| `normalize_var_name` | function | normalize_var_name/1 |  |  |  |  |

| `normalize_var_name` | function | normalize_var_name/1 |  |  |  |  |

| `field_policy_protected?` | function | field_policy_protected?/2 |  |  |  |  |

| `non_attribute_mapped_fields` | function | non_attribute_mapped_fields/2 |  |  |  |  |

| `remove_attributes` | function | remove_attributes/2 |  |  |  |  |

| `remove_attributes` | function | remove_attributes/3 |  |  |  |  |

| `remove_attributes` | function | remove_attributes/3 |  |  |  |  |

| `sanitize_in_memory_mapping` | function | sanitize_in_memory_mapping/2 |  |  |  |  |

| `sanitize_mapping` | function | sanitize_mapping/2 |  |  |  |  |

| `unenforceable_attributes` | function | unenforceable_attributes/2 |  |  |  |  |

| `render` | function | render/2 |  |  |  |  |

| `render` | function | render/2 |  |  |  |  |

| `render` | function | render/1 |  |  |  |  |

| `render_foreign_keys` | function | render_foreign_keys/2 |  |  |  |  |

| `render_table` | function | render_table/1 |  |  |  |  |

| `verify_types` | function | verify_types/1 |  |  |  |  |

| `attribute_field` | function | attribute_field/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `describe_resource` | function | describe_resource/3 |  |  |  |  |

| `manifest_resource` | function | manifest_resource/1 |  |  |  |  |

| `relationship_field` | function | relationship_field/3 |  |  |  |  |

| `render_query` | function | render_query/1 |  |  |  |  |

| `render_query` | function | render_query/1 |  |  |  |  |

| `render_schema` | function | render_schema/1 |  |  |  |  |

| `render_type` | function | render_type/1 |  |  |  |  |

| `semantic_field_name` | function | semantic_field_name/2 |  |  |  |  |

| `literal` | function | literal/1 |  |  |  |  |

| `map_id` | function | map_id/1 |  |  |  |  |

| `module_parts` | function | module_parts/1 |  |  |  |  |

| `module_parts` | function | module_parts/1 |  |  |  |  |

| `predicate_suffix` | function | predicate_suffix/1 |  |  |  |  |

| `predicate_suffix` | function | predicate_suffix/1 |  |  |  |  |

| `remap_template` | function | remap_template/3 |  |  |  |  |

| `render` | function | render/1 |  |  |  |  |

| `render_attribute` | function | render_attribute/1 |  |  |  |  |

| `render_fk_relationship` | function | render_fk_relationship/3 |  |  |  |  |

| `render_join_maps` | function | render_join_maps/2 |  |  |  |  |

| `render_resource` | function | render_resource/2 |  |  |  |  |

| `attribute_shape` | function | attribute_shape/1 |  |  |  |  |

| `max_count` | function | max_count/1 |  |  |  |  |

| `max_count` | function | max_count/1 |  |  |  |  |

| `relationship_shape` | function | relationship_shape/2 |  |  |  |  |

| `render` | function | render/1 |  |  |  |  |

| `render_resource` | function | render_resource/2 |  |  |  |  |

| `attribute_column!` | function | attribute_column!/2 |  |  |  |  |

| `column_definition` | function | column_definition/1 |  |  |  |  |

| `identity_constraints` | function | identity_constraints/1 |  |  |  |  |

| `quote_ident` | function | quote_ident/1 |  |  |  |  |

| `render` | function | render/1 |  |  |  |  |

| `render_foreign_keys` | function | render_foreign_keys/2 |  |  |  |  |

| `render_join_tables` | function | render_join_tables/2 |  |  |  |  |

| `render_table` | function | render_table/1 |  |  |  |  |

| `convert_resource` | function | convert_resource/2 |  |  |  |  |

| `to_mapping` | function | to_mapping/1 |  |  |  |  |

| `compare` | function | compare/2 |  |  |  |  |

| `compare_resources` | function | compare_resources/2 |  |  |  |  |

| `index_resources` | function | index_resources/1 |  |  |  |  |

| `admit_reuse` | function | admit_reuse/2 |  |  |  |  |

| `app_version` | function | app_version/0 |  |  |  |  |

| `bind_environment` | function | bind_environment/2 |  |  |  |  |

| `get` | function | get/3 |  |  |  |  |

| `identity_hash` | function | identity_hash/1 |  |  |  |  |

| `matches?` | function | matches?/2 |  |  |  |  |

| `module_sha256` | function | module_sha256/1 |  |  |  |  |

| `new` | function | new/1 |  |  |  |  |

| `field` | function | field/2 |  |  |  |  |

| `from_ir` | function | from_ir/1 |  |  |  |  |

| `manufacture_input` | function | manufacture_input/1 |  |  |  |  |

| `present` | function | present/2 |  |  |  |  |

| `present` | function | present/2 |  |  |  |  |

| `resolved_material` | function | resolved_material/1 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `strip_sha256` | function | strip_sha256/1 |  |  |  |  |

| `absolute_iri?` | function | absolute_iri?/1 |  |  |  |  |

| `absolute_iri?` | function | absolute_iri?/1 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `canonical_term` | function | canonical_term/1 |  |  |  |  |

| `get` | function | get/3 |  |  |  |  |

| `hash` | function | hash/1 |  |  |  |  |

| `new` | function | new/1 |  |  |  |  |

| `new` | function | new/1 |  |  |  |  |

| `refusal` | function | refusal/4 |  |  |  |  |

| `candidates` | function | candidates/1 |  |  |  |  |

| `candidates` | function | candidates/1 |  |  |  |  |

| `candidates` | function | candidates/1 |  |  |  |  |

| `candidates` | function | candidates/1 |  |  |  |  |

| `candidates` | function | candidates/1 |  |  |  |  |

| `candidates` | function | candidates/1 |  |  |  |  |

| `select` | function | select/1 |  |  |  |  |

| `admit_property` | function | admit_property/2 |  |  |  |  |

| `apply_entry_overrides` | function | apply_entry_overrides/2 |  |  |  |  |

| `apply_overrides` | function | apply_overrides/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compile_entry` | function | compile_entry/2 |  |  |  |  |

| `compile_entry` | function | compile_entry/2 |  |  |  |  |

| `compile_entry` | function | compile_entry/2 |  |  |  |  |

| `diff` | function | diff/2 |  |  |  |  |

| `encode_rdf` | function | encode_rdf/2 |  |  |  |  |

| `entry?` | function | entry?/1 |  |  |  |  |

| `existing_atom` | function | existing_atom/1 |  |  |  |  |

| `existing_atom` | function | existing_atom/1 |  |  |  |  |

| `existing_atom` | function | existing_atom/1 |  |  |  |  |

| `get` | function | get/3 |  |  |  |  |

| `index_manifest_types` | function | index_manifest_types/1 |  |  |  |  |

| `iri_type` | function | iri_type/1 |  |  |  |  |

| `manifest` | function | manifest/1 |  |  |  |  |

| `manifest_json` | function | manifest_json/1 |  |  |  |  |

| `manifest_type` | function | manifest_type/1 |  |  |  |  |

| `maybe_refuse` | function | maybe_refuse/5 |  |  |  |  |

| `maybe_refuse` | function | maybe_refuse/5 |  |  |  |  |

| `normalize_compare` | function | normalize_compare/1 |  |  |  |  |

| `normalize_compare` | function | normalize_compare/1 |  |  |  |  |

| `normalize_compare` | function | normalize_compare/1 |  |  |  |  |

| `normalize_compare` | function | normalize_compare/1 |  |  |  |  |

| `normalize_manifest` | function | normalize_manifest/1 |  |  |  |  |

| `normalize_manifest` | function | normalize_manifest/1 |  |  |  |  |

| `normalize_result` | function | normalize_result/1 |  |  |  |  |

| `normalize_result` | function | normalize_result/1 |  |  |  |  |

| `normalize_result` | function | normalize_result/1 |  |  |  |  |

| `plan` | function | plan/2 |  |  |  |  |

| `plan_hash` | function | plan_hash/2 |  |  |  |  |

| `providers` | function | providers/1 |  |  |  |  |

| `representation` | function | representation/1 |  |  |  |  |

| `representation` | function | representation/1 |  |  |  |  |

| `representation` | function | representation/1 |  |  |  |  |

| `representation` | function | representation/1 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `round_trip` | function | round_trip/2 |  |  |  |  |

| `semantic_ash_compatible?` | function | semantic_ash_compatible?/2 |  |  |  |  |

| `semantic_ash_compatible?` | function | semantic_ash_compatible?/2 |  |  |  |  |

| `semantic_ash_compatible?` | function | semantic_ash_compatible?/2 |  |  |  |  |

| `semantic_differences` | function | semantic_differences/2 |  |  |  |  |

| `semantic_round_trip` | function | semantic_round_trip/2 |  |  |  |  |

| `type_identity` | function | type_identity/1 |  |  |  |  |

| `type_key` | function | type_key/1 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |

| `verify_type` | function | verify_type/1 |  |  |  |  |

| `files` | function | files/2 |  |  |  |  |

| `igniter_files` | function | igniter_files/3 |  |  |  |  |

| `plan_id` | function | plan_id/0 |  |  |  |  |

| `render_contract_tests` | function | render_contract_tests/2 |  |  |  |  |

| `render_elixir` | function | render_elixir/2 |  |  |  |  |

| `render_new_type` | function | render_new_type/2 |  |  |  |  |

| `semantic_type_ids` | function | semantic_type_ids/0 |  |  |  |  |

| `catalogue` | function | catalogue/0 |  |  |  |  |

| `id` | function | id/0 |  |  |  |  |

| `prefixes` | function | prefixes/0 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `catalogue` | function | catalogue/0 |  |  |  |  |

| `id` | function | id/0 |  |  |  |  |

| `prefixes` | function | prefixes/0 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `type` | function | type/6 |  |  |  |  |

| `catalogue` | function | catalogue/0 |  |  |  |  |

| `id` | function | id/0 |  |  |  |  |

| `prefixes` | function | prefixes/0 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `catalogue` | function | catalogue/0 |  |  |  |  |

| `id` | function | id/0 |  |  |  |  |

| `prefixes` | function | prefixes/0 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `plan` | function | plan/1 |  |  |  |  |

| `transform` | function | transform/1 |  |  |  |  |

| `catalogue` | function | catalogue/0 |  |  |  |  |

| `id` | function | id/0 |  |  |  |  |

| `prefixes` | function | prefixes/0 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `catalogue` | function | catalogue/0 |  |  |  |  |

| `id` | function | id/0 |  |  |  |  |

| `name` | function | name/1 |  |  |  |  |

| `prefixes` | function | prefixes/0 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `cardinality_change` | function | cardinality_change/5 |  |  |  |  |

| `change` | function | change/4 |  |  |  |  |

| `classify` | function | classify/1 |  |  |  |  |

| `classify` | function | classify/1 |  |  |  |  |

| `compare_attribute` | function | compare_attribute/3 |  |  |  |  |

| `compare_attributes` | function | compare_attributes/3 |  |  |  |  |

| `compare_relationship` | function | compare_relationship/3 |  |  |  |  |

| `compare_relationships` | function | compare_relationships/3 |  |  |  |  |

| `compare_resource` | function | compare_resource/2 |  |  |  |  |

| `kind` | function | kind/1 |  |  |  |  |

| `narrower_max?` | function | narrower_max?/2 |  |  |  |  |

| `narrower_max?` | function | narrower_max?/2 |  |  |  |  |

| `narrower_max?` | function | narrower_max?/2 |  |  |  |  |

| `not_asserted` | function | not_asserted/0 |  |  |  |  |

| `not_projected` | function | not_projected/1 |  |  |  |  |

| `null` | function | null/0 |  |  |  |  |

| `refused` | function | refused/1 |  |  |  |  |

| `unbound` | function | unbound/0 |  |  |  |  |

| `union_keys` | function | union_keys/2 |  |  |  |  |

| `unknown` | function | unknown/1 |  |  |  |  |

| `unsupported` | function | unsupported/1 |  |  |  |  |

| `value` | function | value/1 |  |  |  |  |

| `wider_max?` | function | wider_max?/2 |  |  |  |  |

| `wider_max?` | function | wider_max?/2 |  |  |  |  |

| `wider_max?` | function | wider_max?/2 |  |  |  |  |

| `AshR2RML.ShortNameCollision.NsA.Widget` | ash_resource |  |  |  |  |  |

| `AshR2RML.ShortNameCollision.NsB.Widget` | ash_resource |  |  |  |  |  |

| `build_envelope` | function | build_envelope/5 |  |  |  |  |

| `canonicalize_map` | function | canonicalize_map/1 |  |  |  |  |

| `canonicalize_val` | function | canonicalize_val/1 |  |  |  |  |

| `canonicalize_val` | function | canonicalize_val/1 |  |  |  |  |

| `compute_digest` | function | compute_digest/4 |  |  |  |  |

| `compute_digest` | function | compute_digest/1 |  |  |  |  |

| `compute_subject_sha` | function | compute_subject_sha/0 |  |  |  |  |

| `default_producer` | function | default_producer/1 |  |  |  |  |

| `dispatch_envelope` | function | dispatch_envelope/2 |  |  |  |  |

| `do_flush` | function | do_flush/1 |  |  |  |  |

| `do_flush` | function | do_flush/1 |  |  |  |  |

| `do_replay_offline` | function | do_replay_offline/2 |  |  |  |  |

| `ensure_inets_started` | function | ensure_inets_started/0 |  |  |  |  |

| `flush` | function | flush/1 |  |  |  |  |

| `generate_run_id` | function | generate_run_id/0 |  |  |  |  |

| `get_control_plane_url` | function | get_control_plane_url/0 |  |  |  |  |

| `get_state` | function | get_state/1 |  |  |  |  |

| `handle_call` | function | handle_call/3 |  |  |  |  |

| `handle_call` | function | handle_call/3 |  |  |  |  |

| `handle_call` | function | handle_call/3 |  |  |  |  |

| `handle_call` | function | handle_call/3 |  |  |  |  |

| `handle_call` | function | handle_call/3 |  |  |  |  |

| `handle_info` | function | handle_info/2 |  |  |  |  |

| `httpc_post` | function | httpc_post/4 |  |  |  |  |

| `init` | function | init/1 |  |  |  |  |

| `normalize_endpoint_url` | function | normalize_endpoint_url/1 |  |  |  |  |

| `normalize_producer` | function | normalize_producer/1 |  |  |  |  |

| `normalize_producer` | function | normalize_producer/1 |  |  |  |  |

| `normalize_producer` | function | normalize_producer/1 |  |  |  |  |

| `push_event` | function | push_event/2 |  |  |  |  |

| `push_events` | function | push_events/2 |  |  |  |  |

| `read_offline_fallback` | function | read_offline_fallback/1 |  |  |  |  |

| `read_offline_fallback` | function | read_offline_fallback/1 |  |  |  |  |

| `replay_offline` | function | replay_offline/2 |  |  |  |  |

| `schedule_flush` | function | schedule_flush/1 |  |  |  |  |

| `sign_digest` | function | sign_digest/2 |  |  |  |  |

| `start_link` | function | start_link/1 |  |  |  |  |

| `stop` | function | stop/1 |  |  |  |  |

| `terminate` | function | terminate/2 |  |  |  |  |

| `verify_chain` | function | verify_chain/1 |  |  |  |  |

| `verify_chain` | function | verify_chain/1 |  |  |  |  |

| `verify_digest` | function | verify_digest/1 |  |  |  |  |

| `verify_digest` | function | verify_digest/1 |  |  |  |  |

| `write_offline_fallback` | function | write_offline_fallback/2 |  |  |  |  |

| `write_offline_fallback` | function | write_offline_fallback/2 |  |  |  |  |

| `check_conformance` | function | check_conformance/2 |  |  |  |  |

| `check_conformance` | function | check_conformance/2 |  |  |  |  |

| `check_conformance` | function | check_conformance/2 |  |  |  |  |

| `check_conformance` | function | check_conformance/2 |  |  |  |  |

| `check_conformance` | function | check_conformance/2 |  |  |  |  |

| `validate_event_schema` | function | validate_event_schema/1 |  |  |  |  |

| `append_ocel_event!` | function | append_ocel_event!/2 |  |  |  |  |

| `attach!` | function | attach!/1 |  |  |  |  |

| `build_notification_ocel_event` | function | build_notification_ocel_event/3 |  |  |  |  |

| `build_ocel_event` | function | build_ocel_event/3 |  |  |  |  |

| `build_reactor_pipeline_event` | function | build_reactor_pipeline_event/3 |  |  |  |  |

| `build_reactor_step_ocel_event` | function | build_reactor_step_ocel_event/3 |  |  |  |  |

| `default_log_path` | function | default_log_path/0 |  |  |  |  |

| `detach_all!` | function | detach_all!/1 |  |  |  |  |

| `duration_ms` | function | duration_ms/1 |  |  |  |  |

| `execution_object` | function | execution_object/1 |  |  |  |  |

| `execution_object` | function | execution_object/1 |  |  |  |  |

| `extract_step_facts` | function | extract_step_facts/2 |  |  |  |  |

| `extract_step_facts` | function | extract_step_facts/2 |  |  |  |  |

| `extract_step_facts` | function | extract_step_facts/2 |  |  |  |  |

| `extract_step_facts` | function | extract_step_facts/2 |  |  |  |  |

| `extract_step_facts` | function | extract_step_facts/2 |  |  |  |  |

| `extract_step_facts` | function | extract_step_facts/2 |  |  |  |  |

| `get_r2rml_class` | function | get_r2rml_class/1 |  |  |  |  |

| `handle_event` | function | handle_event/4 |  |  |  |  |

| `handle_notification_event` | function | handle_notification_event/4 |  |  |  |  |

| `handle_reactor_pipeline_event` | function | handle_reactor_pipeline_event/4 |  |  |  |  |

| `handle_reactor_step_event` | function | handle_reactor_step_event/4 |  |  |  |  |

| `safe_step_name` | function | safe_step_name/1 |  |  |  |  |

| `safe_step_name` | function | safe_step_name/1 |  |  |  |  |

| `safe_step_name` | function | safe_step_name/1 |  |  |  |  |

| `safe_step_name` | function | safe_step_name/1 |  |  |  |  |

| `safe_step_name` | function | safe_step_name/1 |  |  |  |  |

| `safe_step_name` | function | safe_step_name/1 |  |  |  |  |

| `with_execution_object` | function | with_execution_object/3 |  |  |  |  |

| `container_running?` | function | container_running?/0 |  |  |  |  |

| `ensure_infra` | function | ensure_infra/0 |  |  |  |  |

| `network_exists?` | function | network_exists?/0 |  |  |  |  |

| `skip_reason` | function | skip_reason/0 |  |  |  |  |

| `class_iri` | function | class_iri/0 |  |  |  |  |

| `concept_scheme_iri` | function | concept_scheme_iri/0 |  |  |  |  |

| `contract` | function | contract/1 |  |  |  |  |

| `datatype_iri` | function | datatype_iri/0 |  |  |  |  |

| `decode` | function | decode/2 |  |  |  |  |

| `encode` | function | encode/2 |  |  |  |  |

| `exported` | function | exported/2 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `from_rdf_lexical` | function | from_rdf_lexical/1 |  |  |  |  |

| `semantic_kind` | function | semantic_kind/0 |  |  |  |  |

| `semantic_type?` | function | semantic_type?/1 |  |  |  |  |

| `semantic_type?` | function | semantic_type?/1 |  |  |  |  |

| `shacl_constraints` | function | shacl_constraints/0 |  |  |  |  |

| `to_rdf` | function | to_rdf/1 |  |  |  |  |

| `to_rdf_lexical` | function | to_rdf_lexical/1 |  |  |  |  |

| `xsd_datatype` | function | xsd_datatype/0 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `constraints` | function | constraints/0 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `equal?` | function | equal?/2 |  |  |  |  |

| `equal?` | function | equal?/2 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `storage_type` | function | storage_type/1 |  |  |  |  |

| `to_rdf` | function | to_rdf/1 |  |  |  |  |

| `to_rdf` | function | to_rdf/1 |  |  |  |  |

| `validate` | function | validate/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `constraints` | function | constraints/0 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `prefix_ok?` | function | prefix_ok?/2 |  |  |  |  |

| `prefix_ok?` | function | prefix_ok?/2 |  |  |  |  |

| `storage_type` | function | storage_type/1 |  |  |  |  |

| `to_rdf` | function | to_rdf/1 |  |  |  |  |

| `to_rdf` | function | to_rdf/1 |  |  |  |  |

| `validate` | function | validate/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `storage_type` | function | storage_type/1 |  |  |  |  |

| `to_rdf` | function | to_rdf/1 |  |  |  |  |

| `to_rdf` | function | to_rdf/1 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `constraints` | function | constraints/0 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `numeric?` | function | numeric?/1 |  |  |  |  |

| `storage_type` | function | storage_type/1 |  |  |  |  |

| `to_rdf` | function | to_rdf/1 |  |  |  |  |

| `to_rdf` | function | to_rdf/1 |  |  |  |  |

| `validate` | function | validate/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_input` | function | cast_input/2 |  |  |  |  |

| `cast_stored` | function | cast_stored/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `dump_to_native` | function | dump_to_native/2 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `from_rdf` | function | from_rdf/1 |  |  |  |  |

| `storage_type` | function | storage_type/1 |  |  |  |  |

| `to_rdf` | function | to_rdf/1 |  |  |  |  |

| `to_rdf` | function | to_rdf/1 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |

| `catalog` | function | catalog/1 |  |  |  |  |

| `catalog` | function | catalog/1 |  |  |  |  |

| `catalog` | function | catalog/1 |  |  |  |  |

| `check_expected` | function | check_expected/2 |  |  |  |  |

| `check_expected` | function | check_expected/2 |  |  |  |  |

| `check_expected` | function | check_expected/2 |  |  |  |  |

| `do_verify` | function | do_verify/2 |  |  |  |  |

| `expected_catalog` | function | expected_catalog/1 |  |  |  |  |

| `opts_refusal` | function | opts_refusal/1 |  |  |  |  |

| `query` | function | query/2 |  |  |  |  |

| `query` | function | query/2 |  |  |  |  |

| `query` | function | query/2 |  |  |  |  |

| `query` | function | query/2 |  |  |  |  |

| `query_all` | function | query_all/1 |  |  |  |  |

| `query_all` | function | query_all/1 |  |  |  |  |

| `query_all` | function | query_all/1 |  |  |  |  |

| `run` | function | run/3 |  |  |  |  |

| `verify` | function | verify/2 |  |  |  |  |

| `verify` | function | verify/2 |  |  |  |  |

| `verify` | function | verify/2 |  |  |  |  |

| `verify` | function | verify/2 |  |  |  |  |

| `bad_max` | function | bad_max/1 |  |  |  |  |

| `bad_options` | function | bad_options/1 |  |  |  |  |

| `do_run` | function | do_run/2 |  |  |  |  |

| `query` | function | query/2 |  |  |  |  |

| `run` | function | run/2 |  |  |  |  |

| `run` | function | run/2 |  |  |  |  |

| `run` | function | run/2 |  |  |  |  |

| `run` | function | run/2 |  |  |  |  |

| `run_request` | function | run_request/2 |  |  |  |  |

| `run_request` | function | run_request/2 |  |  |  |  |

| `whole` | function | whole/1 |  |  |  |  |

| `fetch` | function | fetch/2 |  |  |  |  |

| `ids` | function | ids/1 |  |  |  |  |

| `load` | function | load/1 |  |  |  |  |

| `new` | function | new/1 |  |  |  |  |

| `scope_refusal` | function | scope_refusal/2 |  |  |  |  |

| `select` | function | select/2 |  |  |  |  |

| `select` | function | select/2 |  |  |  |  |

| `select_valid` | function | select_valid/2 |  |  |  |  |

| `snapshot` | function | snapshot/1 |  |  |  |  |

| `valid_ids` | function | valid_ids/1 |  |  |  |  |

| `check` | function | check/1 |  |  |  |  |

| `check` | function | check/1 |  |  |  |  |

| `compatible_pair?` | function | compatible_pair?/2 |  |  |  |  |

| `matrix` | function | matrix/1 |  |  |  |  |

| `observe_only` | function | observe_only/1 |  |  |  |  |

| `refusal` | function | refusal/3 |  |  |  |  |

| `structs` | function | structs/1 |  |  |  |  |

| `unique_graphs` | function | unique_graphs/1 |  |  |  |  |

| `unique_sources` | function | unique_sources/1 |  |  |  |  |

| `versions` | function | versions/1 |  |  |  |  |

| `snapshot` | function | snapshot/1 |  |  |  |  |

| `connection` | function | connection/2 |  |  |  |  |

| `cursor` | function | cursor/3 |  |  |  |  |

| `decode` | function | decode/2 |  |  |  |  |

| `edge` | function | edge/3 |  |  |  |  |

| `end_cursor` | function | end_cursor/1 |  |  |  |  |

| `end_cursor` | function | end_cursor/1 |  |  |  |  |

| `invalid_cursor` | function | invalid_cursor/1 |  |  |  |  |

| `page` | function | page/2 |  |  |  |  |

| `page` | function | page/2 |  |  |  |  |

| `page` | function | page/2 |  |  |  |  |

| `page` | function | page/2 |  |  |  |  |

| `refuse` | function | refuse/3 |  |  |  |  |

| `result_prefix` | function | result_prefix/1 |  |  |  |  |

| `row_digest` | function | row_digest/1 |  |  |  |  |

| `start_index` | function | start_index/3 |  |  |  |  |

| `start_index` | function | start_index/3 |  |  |  |  |

| `start_index` | function | start_index/3 |  |  |  |  |

| `validate_first` | function | validate_first/1 |  |  |  |  |

| `validate_first` | function | validate_first/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `canonical_hash` | function | canonical_hash/1 |  |  |  |  |

| `capability_allowlist` | function | capability_allowlist/0 |  |  |  |  |

| `capability_refusal` | function | capability_refusal/1 |  |  |  |  |

| `digest` | function | digest/1 |  |  |  |  |

| `digest_refusal` | function | digest_refusal/1 |  |  |  |  |

| `exact_subject?` | function | exact_subject?/2 |  |  |  |  |

| `exact_subject?` | function | exact_subject?/2 |  |  |  |  |

| `identity` | function | identity/1 |  |  |  |  |

| `shape_refusal` | function | shape_refusal/3 |  |  |  |  |

| `validate_authority` | function | validate_authority/1 |  |  |  |  |

| `validate_authority` | function | validate_authority/1 |  |  |  |  |

| `validate_capabilities` | function | validate_capabilities/1 |  |  |  |  |

| `validate_capabilities` | function | validate_capabilities/1 |  |  |  |  |

| `validate_digest` | function | validate_digest/2 |  |  |  |  |

| `validate_digest` | function | validate_digest/2 |  |  |  |  |

| `validate_ontology` | function | validate_ontology/2 |  |  |  |  |

| `validate_ontology` | function | validate_ontology/2 |  |  |  |  |

| `validate_ontology` | function | validate_ontology/2 |  |  |  |  |

| `validate_path` | function | validate_path/2 |  |  |  |  |

| `validate_path` | function | validate_path/2 |  |  |  |  |

| `validate_standing` | function | validate_standing/1 |  |  |  |  |

| `validate_standing` | function | validate_standing/1 |  |  |  |  |

| `validate_text` | function | validate_text/2 |  |  |  |  |

| `validate_text` | function | validate_text/2 |  |  |  |  |

| `validate_version` | function | validate_version/1 |  |  |  |  |

| `validate_version` | function | validate_version/1 |  |  |  |  |

| `execute` | function | execute/2 |  |  |  |  |

| `maybe_put` | function | maybe_put/3 |  |  |  |  |

| `maybe_put` | function | maybe_put/3 |  |  |  |  |

| `aggregate_standing` | function | aggregate_standing/2 |  |  |  |  |

| `bind_catalog` | function | bind_catalog/2 |  |  |  |  |

| `bound_refusal` | function | bound_refusal/2 |  |  |  |  |

| `call_engine` | function | call_engine/3 |  |  |  |  |

| `canonicalize_observation` | function | canonicalize_observation/2 |  |  |  |  |

| `catalog_intact` | function | catalog_intact/1 |  |  |  |  |

| `catalog_intact` | function | catalog_intact/1 |  |  |  |  |

| `catalog_matches_plan` | function | catalog_matches_plan/2 |  |  |  |  |

| `check_drift` | function | check_drift/2 |  |  |  |  |

| `check_engine` | function | check_engine/1 |  |  |  |  |

| `check_recorded_digest` | function | check_recorded_digest/2 |  |  |  |  |

| `check_running_bound` | function | check_running_bound/2 |  |  |  |  |

| `check_running_bound` | function | check_running_bound/2 |  |  |  |  |

| `check_stage_binding` | function | check_stage_binding/3 |  |  |  |  |

| `drift_result` | function | drift_result/3 |  |  |  |  |

| `drift_result` | function | drift_result/3 |  |  |  |  |

| `enforce_result_bound` | function | enforce_result_bound/2 |  |  |  |  |

| `execute` | function | execute/2 |  |  |  |  |

| `execute` | function | execute/2 |  |  |  |  |

| `execute` | function | execute/2 |  |  |  |  |

| `execute` | function | execute/2 |  |  |  |  |

| `fetch_bound_contract` | function | fetch_bound_contract/2 |  |  |  |  |

| `malformed` | function | malformed/3 |  |  |  |  |

| `merge` | function | merge/2 |  |  |  |  |

| `merge` | function | merge/2 |  |  |  |  |

| `merge_subject` | function | merge_subject/1 |  |  |  |  |

| `merge_values` | function | merge_values/2 |  |  |  |  |

| `merge_values` | function | merge_values/2 |  |  |  |  |

| `plan_refusal` | function | plan_refusal/3 |  |  |  |  |

| `read_bytes` | function | read_bytes/1 |  |  |  |  |

| `read_bytes` | function | read_bytes/1 |  |  |  |  |

| `replay` | function | replay/3 |  |  |  |  |

| `replay` | function | replay/3 |  |  |  |  |

| `row_identity` | function | row_identity/1 |  |  |  |  |

| `run` | function | run/5 |  |  |  |  |

| `run_stage` | function | run_stage/7 |  |  |  |  |

| `run_stages` | function | run_stages/4 |  |  |  |  |

| `safe_engine_call` | function | safe_engine_call/3 |  |  |  |  |

| `safe_extension` | function | safe_extension/1 |  |  |  |  |

| `semantic_sha256` | function | semantic_sha256/2 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `snapshot_stage` | function | snapshot_stage/1 |  |  |  |  |

| `stage_refusal` | function | stage_refusal/2 |  |  |  |  |

| `stages_match_catalog` | function | stages_match_catalog/2 |  |  |  |  |

| `validate_observation` | function | validate_observation/2 |  |  |  |  |

| `validate_observation` | function | validate_observation/2 |  |  |  |  |

| `with_stage_inputs` | function | with_stage_inputs/3 |  |  |  |  |

| `with_stage_inputs` | function | with_stage_inputs/3 |  |  |  |  |

| `write_files` | function | write_files/3 |  |  |  |  |

| `write_snapshot` | function | write_snapshot/2 |  |  |  |  |

| `catalog` | function | catalog/1 |  |  |  |  |

| `session` | function | session/1 |  |  |  |  |

| `snapshot` | function | snapshot/1 |  |  |  |  |

| `snapshot` | function | snapshot/1 |  |  |  |  |

| `capabilities` | function | capabilities/1 |  |  |  |  |

| `capabilities` | function | capabilities/1 |  |  |  |  |

| `capabilities` | function | capabilities/1 |  |  |  |  |

| `capability_refusal` | function | capability_refusal/1 |  |  |  |  |

| `contained` | function | contained/4 |  |  |  |  |

| `decode` | function | decode/2 |  |  |  |  |

| `default_root` | function | default_root/0 |  |  |  |  |

| `load` | function | load/2 |  |  |  |  |

| `load` | function | load/2 |  |  |  |  |

| `load` | function | load/2 |  |  |  |  |

| `load_all` | function | load_all/1 |  |  |  |  |

| `load_all` | function | load_all/1 |  |  |  |  |

| `load_all` | function | load_all/1 |  |  |  |  |

| `load_paths` | function | load_paths/2 |  |  |  |  |

| `optional_digest` | function | optional_digest/1 |  |  |  |  |

| `optional_digest` | function | optional_digest/1 |  |  |  |  |

| `optional_resolve` | function | optional_resolve/2 |  |  |  |  |

| `optional_resolve` | function | optional_resolve/2 |  |  |  |  |

| `read` | function | read/2 |  |  |  |  |

| `refusal` | function | refusal/3 |  |  |  |  |

| `resolve` | function | resolve/3 |  |  |  |  |

| `resolve` | function | resolve/3 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `snapshot` | function | snapshot/1 |  |  |  |  |

| `symlinked?` | function | symlinked?/2 |  |  |  |  |

| `version` | function | version/1 |  |  |  |  |

| `version` | function | version/1 |  |  |  |  |

| `version` | function | version/1 |  |  |  |  |

| `from_session` | function | from_session/1 |  |  |  |  |

| `do_plan` | function | do_plan/3 |  |  |  |  |

| `ensure_capability` | function | ensure_capability/2 |  |  |  |  |

| `options_refusal` | function | options_refusal/1 |  |  |  |  |

| `plan` | function | plan/3 |  |  |  |  |

| `plan` | function | plan/3 |  |  |  |  |

| `plan` | function | plan/3 |  |  |  |  |

| `plan` | function | plan/3 |  |  |  |  |

| `plan_all` | function | plan_all/2 |  |  |  |  |

| `stage_for` | function | stage_for/1 |  |  |  |  |

| `valid_capability` | function | valid_capability/1 |  |  |  |  |

| `attach` | function | attach/3 |  |  |  |  |

| `exact_source?` | function | exact_source?/2 |  |  |  |  |

| `row_hash` | function | row_hash/3 |  |  |  |  |

| `strip` | function | strip/1 |  |  |  |  |

| `subject` | function | subject/1 |  |  |  |  |

| `authority?` | function | authority?/1 |  |  |  |  |

| `authority?` | function | authority?/1 |  |  |  |  |

| `canonical_stages` | function | canonical_stages/1 |  |  |  |  |

| `capability?` | function | capability?/1 |  |  |  |  |

| `common_capabilities` | function | common_capabilities/1 |  |  |  |  |

| `core` | function | core/1 |  |  |  |  |

| `digest?` | function | digest?/2 |  |  |  |  |

| `digest?` | function | digest?/2 |  |  |  |  |

| `hash` | function | hash/1 |  |  |  |  |

| `merge_mode?` | function | merge_mode?/1 |  |  |  |  |

| `merge_mode?` | function | merge_mode?/1 |  |  |  |  |

| `new` | function | new/4 |  |  |  |  |

| `new` | function | new/4 |  |  |  |  |

| `new` | function | new/4 |  |  |  |  |

| `non_empty_ids?` | function | non_empty_ids?/1 |  |  |  |  |

| `non_empty_ids?` | function | non_empty_ids?/1 |  |  |  |  |

| `ontology_binding` | function | ontology_binding/1 |  |  |  |  |

| `ontology_binding_matches?` | function | ontology_binding_matches?/1 |  |  |  |  |

| `ontology_consistent?` | function | ontology_consistent?/1 |  |  |  |  |

| `plan_id` | function | plan_id/1 |  |  |  |  |

| `positive_integer?` | function | positive_integer?/2 |  |  |  |  |

| `positive_integer?` | function | positive_integer?/2 |  |  |  |  |

| `refusal` | function | refusal/3 |  |  |  |  |

| `stage_capabilities?` | function | stage_capabilities?/1 |  |  |  |  |

| `stages_match?` | function | stages_match?/2 |  |  |  |  |

| `stages_match?` | function | stages_match?/2 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |

| `build` | function | build/4 |  |  |  |  |

| `evidence_digests` | function | evidence_digests/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit` | function | admit/1 |  |  |  |  |

| `admit_each` | function | admit_each/1 |  |  |  |  |

| `consistent_graphs` | function | consistent_graphs/1 |  |  |  |  |

| `consistent_sources` | function | consistent_sources/1 |  |  |  |  |

| `digest` | function | digest/1 |  |  |  |  |

| `fetch` | function | fetch/2 |  |  |  |  |

| `fetch` | function | fetch/2 |  |  |  |  |

| `fetch` | function | fetch/2 |  |  |  |  |

| `refusal` | function | refusal/3 |  |  |  |  |

| `unique_ids` | function | unique_ids/1 |  |  |  |  |

| `build` | function | build/3 |  |  |  |  |

| `compute_sha256` | function | compute_sha256/3 |  |  |  |  |

| `equivalent?` | function | equivalent?/2 |  |  |  |  |

| `normal_form?` | function | normal_form?/1 |  |  |  |  |

| `normalize_row` | function | normalize_row/1 |  |  |  |  |

| `normalize_row` | function | normalize_row/1 |  |  |  |  |

| `normalize_value` | function | normalize_value/1 |  |  |  |  |

| `normalize_value` | function | normalize_value/1 |  |  |  |  |

| `normalize_value` | function | normalize_value/1 |  |  |  |  |

| `normalize_value` | function | normalize_value/1 |  |  |  |  |

| `normalize_value` | function | normalize_value/1 |  |  |  |  |

| `normalize_value` | function | normalize_value/1 |  |  |  |  |

| `normalize_value` | function | normalize_value/1 |  |  |  |  |

| `normalize_value` | function | normalize_value/1 |  |  |  |  |

| `normalize_value` | function | normalize_value/1 |  |  |  |  |

| `refusal` | function | refusal/3 |  |  |  |  |

| `row_sort_key` | function | row_sort_key/1 |  |  |  |  |

| `source_counts` | function | source_counts/1 |  |  |  |  |

| `source_index` | function | source_index/1 |  |  |  |  |

| `standings` | function | standings/0 |  |  |  |  |

| `subject_index` | function | subject_index/1 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |

| `app_version` | function | app_version/0 |  |  |  |  |

| `digest` | function | digest/2 |  |  |  |  |

| `digest` | function | digest/2 |  |  |  |  |

| `digest` | function | digest/2 |  |  |  |  |

| `encode!` | function | encode!/1 |  |  |  |  |

| `fetch` | function | fetch/2 |  |  |  |  |

| `from_source` | function | from_source/2 |  |  |  |  |

| `from_source` | function | from_source/2 |  |  |  |  |

| `from_source` | function | from_source/2 |  |  |  |  |

| `non_empty` | function | non_empty/2 |  |  |  |  |

| `non_empty` | function | non_empty/2 |  |  |  |  |

| `non_empty_value?` | function | non_empty_value?/1 |  |  |  |  |

| `put_optional_provenance` | function | put_optional_provenance/2 |  |  |  |  |

| `put_optional_provenance` | function | put_optional_provenance/2 |  |  |  |  |

| `put_optional_provenance` | function | put_optional_provenance/2 |  |  |  |  |

| `receipt_digest` | function | receipt_digest/1 |  |  |  |  |

| `receipt_digest` | function | receipt_digest/1 |  |  |  |  |

| `receipt_digest` | function | receipt_digest/1 |  |  |  |  |

| `receipt_digest` | function | receipt_digest/1 |  |  |  |  |

| `refusal` | function | refusal/3 |  |  |  |  |

| `replay_identity` | function | replay_identity/2 |  |  |  |  |

| `seal` | function | seal/1 |  |  |  |  |

| `sha256?` | function | sha256?/1 |  |  |  |  |

| `stringify` | function | stringify/1 |  |  |  |  |

| `valid_source?` | function | valid_source?/0 |  |  |  |  |

| `valid_source?` | function | valid_source?/1 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |

| `canonical_json` | function | canonical_json/1 |  |  |  |  |

| `decode_object` | function | decode_object/2 |  |  |  |  |

| `decode_receipt` | function | decode_receipt/1 |  |  |  |  |

| `decode_receipt` | function | decode_receipt/1 |  |  |  |  |

| `decode_result` | function | decode_result/1 |  |  |  |  |

| `decode_result` | function | decode_result/1 |  |  |  |  |

| `decode_value` | function | decode_value/1 |  |  |  |  |

| `decode_value` | function | decode_value/1 |  |  |  |  |

| `decode_value` | function | decode_value/1 |  |  |  |  |

| `decode_value` | function | decode_value/1 |  |  |  |  |

| `decode_value` | function | decode_value/1 |  |  |  |  |

| `decode_value` | function | decode_value/1 |  |  |  |  |

| `decode_value` | function | decode_value/1 |  |  |  |  |

| `decode_value` | function | decode_value/1 |  |  |  |  |

| `decode_value` | function | decode_value/1 |  |  |  |  |

| `decode_value` | function | decode_value/1 |  |  |  |  |

| `digest` | function | digest/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `encode_members` | function | encode_members/1 |  |  |  |  |

| `encode_pairs` | function | encode_pairs/1 |  |  |  |  |

| `encode_receipt!` | function | encode_receipt!/1 |  |  |  |  |

| `encode_result!` | function | encode_result!/1 |  |  |  |  |

| `encode_session!` | function | encode_session!/1 |  |  |  |  |

| `enum` | function | enum/4 |  |  |  |  |

| `fields` | function | fields/3 |  |  |  |  |

| `key_string` | function | key_string/1 |  |  |  |  |

| `key_string` | function | key_string/1 |  |  |  |  |

| `key_string` | function | key_string/1 |  |  |  |  |

| `plain_keys?` | function | plain_keys?/1 |  |  |  |  |

| `receipt` | function | receipt/1 |  |  |  |  |

| `refuse` | function | refuse/3 |  |  |  |  |

| `reserved_keys?` | function | reserved_keys?/1 |  |  |  |  |

| `result` | function | result/1 |  |  |  |  |

| `session` | function | session/1 |  |  |  |  |

| `signature` | function | signature/1 |  |  |  |  |

| `signature` | function | signature/1 |  |  |  |  |

| `signature` | function | signature/1 |  |  |  |  |

| `signature` | function | signature/1 |  |  |  |  |

| `stringify` | function | stringify/1 |  |  |  |  |

| `tagged` | function | tagged/2 |  |  |  |  |

| `verify_receipt_json` | function | verify_receipt_json/4 |  |  |  |  |

| `check_catalog` | function | check_catalog/1 |  |  |  |  |

| `check_reconstruction` | function | check_reconstruction/1 |  |  |  |  |

| `compare_rebuilt` | function | compare_rebuilt/2 |  |  |  |  |

| `new` | function | new/0 |  |  |  |  |

| `summary` | function | summary/1 |  |  |  |  |

| `verify` | function | verify/2 |  |  |  |  |

| `absolute_identity?` | function | absolute_identity?/1 |  |  |  |  |

| `absolute_identity?` | function | absolute_identity?/1 |  |  |  |  |

| `fetch` | function | fetch/2 |  |  |  |  |

| `fingerprint` | function | fingerprint/1 |  |  |  |  |

| `new` | function | new/1 |  |  |  |  |

| `new` | function | new/1 |  |  |  |  |

| `non_empty?` | function | non_empty?/1 |  |  |  |  |

| `refusal` | function | refusal/3 |  |  |  |  |

| `same?` | function | same?/2 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `verify` | function | verify/2 |  |  |  |  |

| `catalog` | function | catalog/1 |  |  |  |  |

| `collect_atoms` | function | collect_atoms/2 |  |  |  |  |

| `collect_atoms` | function | collect_atoms/2 |  |  |  |  |

| `collect_atoms` | function | collect_atoms/2 |  |  |  |  |

| `collect_atoms` | function | collect_atoms/2 |  |  |  |  |

| `contract` | function | contract/2 |  |  |  |  |

| `plan` | function | plan/1 |  |  |  |  |

| `refusal_codes` | function | refusal_codes/0 |  |  |  |  |

| `type_atoms` | function | type_atoms/2 |  |  |  |  |

| `absolute_iri` | function | absolute_iri/2 |  |  |  |  |

| `absolute_iri` | function | absolute_iri/2 |  |  |  |  |

| `exactly_one_logical_table` | function | exactly_one_logical_table/2 |  |  |  |  |

| `known_attributes` | function | known_attributes/3 |  |  |  |  |

| `known_relationships` | function | known_relationships/2 |  |  |  |  |

| `optional_absolute_iri` | function | optional_absolute_iri/2 |  |  |  |  |

| `optional_absolute_iri` | function | optional_absolute_iri/2 |  |  |  |  |

| `present?` | function | present?/1 |  |  |  |  |

| `primary_key_in_template` | function | primary_key_in_template/2 |  |  |  |  |

| `primary_key_in_template` | function | primary_key_in_template/2 |  |  |  |  |

| `unique_attribute_mapping` | function | unique_attribute_mapping/2 |  |  |  |  |

| `valid_predicates` | function | valid_predicates/3 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |

| `verify` | function | verify/1 |  |  |  |  |

| `capabilities_allowed?` | function | capabilities_allowed?/2 |  |  |  |  |

| `cells` | function | cells/2 |  |  |  |  |

| `country_for` | function | country_for/1 |  |  |  |  |

| `hash` | function | hash/1 |  |  |  |  |

| `rendezvous_score` | function | rendezvous_score/2 |  |  |  |  |

| `residency_allowed?` | function | residency_allowed?/4 |  |  |  |  |

| `route` | function | route/3 |  |  |  |  |

| `serialize_node` | function | serialize_node/2 |  |  |  |  |

| `serialize_node` | function | serialize_node/2 |  |  |  |  |

| `serialize_node` | function | serialize_node/2 |  |  |  |  |

| `to_owl_turtle` | function | to_owl_turtle/2 |  |  |  |  |

| `standard_e2o_qualifiers` | function | standard_e2o_qualifiers/0 |  |  |  |  |

| `standard_lifecycles` | function | standard_lifecycles/0 |  |  |  |  |

| `standard_o2o_qualifiers` | function | standard_o2o_qualifiers/0 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |

| `admit` | function | admit/3 |  |  |  |  |

| `authorize_do` | function | authorize_do/2 |  |  |  |  |

| `constraint` | function | constraint/4 |  |  |  |  |

| `default_assignment` | function | default_assignment/0 |  |  |  |  |

| `default_profile` | function | default_profile/0 |  |  |  |  |

| `design_space` | function | design_space/0 |  |  |  |  |

| `dimension` | function | dimension/3 |  |  |  |  |

| `operational_ready?` | function | operational_ready?/1 |  |  |  |  |

| `operational_ready?` | function | operational_ready?/1 |  |  |  |  |

| `profile_sha256` | function | profile_sha256/1 |  |  |  |  |

| `validate_profile` | function | validate_profile/1 |  |  |  |  |

| `verify_evidence` | function | verify_evidence/3 |  |  |  |  |

| `execute` | function | execute/2 |  |  |  |  |

| `igniter` | function | igniter/1 |  |  |  |  |

| `run` | function | run/1 |  |  |  |  |

| `run` | function | run/1 |  |  |  |  |

| `Mix.Tasks.AshR2rml.Install` | ash_resource |  |  |  |  |  |

| `add_starter_dsl_block` | function | add_starter_dsl_block/2 |  |  |  |  |

| `igniter` | function | igniter/1 |  |  |  |  |

| `info` | function | info/2 |  |  |  |  |

| `run` | function | run/1 |  |  |  |  |

| `run` | function | run/1 |  |  |  |  |

| `run` | function | run/1 |  |  |  |  |

| `run` | function | run/1 |  |  |  |  |

| `run` | function | run/1 |  |  |  |  |

| `run` | function | run/1 |  |  |  |  |

| `run` | function | run/1 |  |  |  |  |

| `run` | function | run/1 |  |  |  |  |

| `run` | function | run/1 |  |  |  |  |

| `run` | function | run/1 |  |  |  |  |

| `run` | function | run/1 |  |  |  |  |

| `MyApp.Person` | ash_resource |  |  |  |  |  |

| `receipt` | function | receipt/1 |  |  |  |  |

| `__r2rml_domains__` | function | __r2rml_domains__/0 |  |  |  |  |

| `assert_read_only!` | function | assert_read_only!/2 |  |  |  |  |

| `canonical_sdl` | function | canonical_sdl/1 |  |  |  |  |

| `receipt` | function | receipt/1 |  |  |  |  |

| `resources` | function | resources/1 |  |  |  |  |

| `schema_sha` | function | schema_sha/1 |  |  |  |  |

| `sdl` | function | sdl/1 |  |  |  |  |

| `cells` | function | cells/4 |  |  |  |  |

| `contains_secret?` | function | contains_secret?/1 |  |  |  |  |

| `maybe_refuse` | function | maybe_refuse/3 |  |  |  |  |

| `maybe_refuse` | function | maybe_refuse/3 |  |  |  |  |

| `plan` | function | plan/3 |  |  |  |  |

| `role` | function | role/5 |  |  |  |  |

| `roles` | function | roles/1 |  |  |  |  |

| `validate` | function | validate/1 |  |  |  |  |

| `compile` | function | compile/2 |  |  |  |  |

| `compare` | function | compare/2 |  |  |  |  |

| `execute` | function | execute/2 |  |  |  |  |

| `reconstruct` | function | reconstruct/2 |  |  |  |  |

| `reconstruct` | function | reconstruct/2 |  |  |  |  |

| `refuse` | function | refuse/3 |  |  |  |  |

| `verify` | function | verify/5 |  |  |  |  |

| `execute` | function | execute/2 |  |  |  |  |

| `admitted_candidates` | function | admitted_candidates/1 |  |  |  |  |

| `build_plan` | function | build_plan/3 |  |  |  |  |

| `canonical` | function | canonical/1 |  |  |  |  |

| `canonical_relationship` | function | canonical_relationship/1 |  |  |  |  |

| `exact_binding` | function | exact_binding/2 |  |  |  |  |

| `falsifiers_clear` | function | falsifiers_clear/2 |  |  |  |  |

| `observe` | function | observe/2 |  |  |  |  |

| `observe` | function | observe/2 |  |  |  |  |

| `plans` | function | plans/2 |  |  |  |  |

| `plans` | function | plans/2 |  |  |  |  |

| `required_checks_pass` | function | required_checks_pass/2 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `enumerate` | function | enumerate/2 |  |  |  |  |

| `logical_cardinality` | function | logical_cardinality/2 |  |  |  |  |

| `new` | function | new/3 |  |  |  |  |


<!-- ============================================================= -->
<!-- AGENT-FORBIDDEN-END: nothing below this line may describe     -->
<!-- code behavior.                                                -->
<!-- ============================================================= -->
