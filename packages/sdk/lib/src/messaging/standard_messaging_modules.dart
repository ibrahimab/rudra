import 'application_messaging_module.dart';

import '../workflow/messaging/workflow_messaging_module.dart';

/// Returns the messaging modules enabled in standard Rudra.
///
/// Feature composition is explicit and deterministic.
///
/// Each invocation returns an independent collection of modules
/// without acquiring communication resources or executing
/// application operations.
List<ApplicationMessagingModule> standard_messaging_modules() {
  return [const WorkflowMessagingModule()];
}
