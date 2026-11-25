import 'application_messaging_module.dart';

import '../state/messaging/state_messaging_module.dart';

import '../workflow/messaging/workflow_messaging_module.dart';
import '../workflow/workflow_runtime.dart';

/// Returns the messaging modules enabled in standard Rudra.
///
/// [workflow_runtime] optionally supplies the immutable workflow
/// configuration used for application state serialization.
///
/// When omitted, the state messaging module selects the
/// standard workflow runtime.
///
/// Feature composition is explicit and deterministic.
///
/// Each invocation returns an independent collection of modules
/// without acquiring communication resources or executing
/// application operations.
///
/// Example:
/// ```dart
/// final modules = standard_messaging_modules(
///   workflow_runtime: runtime,
/// );
///
/// final codecs = create_application_message_codecs(
///   modules: modules,
/// );
/// ```
List<ApplicationMessagingModule> standard_messaging_modules({
  WorkflowRuntime? workflow_runtime,
}) {
  return [
    const WorkflowMessagingModule(),
    StateMessagingModule(runtime: workflow_runtime),
  ];
}
