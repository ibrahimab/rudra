/// Public workflow domain and application capabilities.
library;

/// Workflow identity.
export 'workflow_identity.dart';

/// Immutable lifecycle and typed domain slice contracts.
export 'states/workflow_lifecycle.dart';
export 'states/workflow_slice.dart';

/// Domain events.

export 'events/workflow_event.dart';
export 'events/workflow_start_event.dart';
export 'events/workflow_started_event.dart';
export 'events/workflow_ended_event.dart';
export 'events/workflow_stop_event.dart';
export 'states/workflow_stop_requested_state.dart';

/// Submission contracts.
export 'event_manager.dart';
export 'event_submission_store.dart';
export 'event_submission_receipt.dart';
export 'event_submission_exception.dart';

/// Workflow states.
export 'states/workflow_state.dart';
export 'states/workflow_initial_state.dart';
export 'states/workflow_start_requested_state.dart';
export 'states/workflow_active_state.dart';
export 'states/workflow_ended_state.dart';

/// Workflow state machine.
export 'workflow_flow.dart';
export 'workflow_flow_exception.dart';
export 'workflow_state_machine.dart';
export 'workflow_transition_exception.dart';
export 'workflow_runtime.dart';

/// Extension contracts and module registration.
export 'transitions/workflow_transition.dart';
export 'behaviors/workflow_behavior.dart';
export 'modules/workflow_module.dart';
export 'modules/workflow_module_registry.dart';
export 'modules/lifecycle_workflow_module.dart';

/// Registry-driven event serialization.
export 'serialization/workflow_event_serializer.dart';
export 'serialization/workflow_event_codec.dart';

/// Durable workflow processing contracts.
/// Workflow processing contracts and orchestration.
export 'processing/workflow_processing_models.dart';
export 'processing/workflow_inbox.dart';
export 'processing/workflow_identity_provider.dart';
export 'processing/workflow_committer.dart';
export 'processing/workflow_processor.dart';
export 'processing/workflow_commit_exception.dart';
export 'processing/workflow_submission_resolution.dart';
export 'processing/workflow_processing_result.dart';
export 'processing/workflow_quarantine.dart';

/// Read-only workflow history and restoration.
export 'reading/workflow_history_store.dart';
export 'reading/workflow_state_reader.dart';
