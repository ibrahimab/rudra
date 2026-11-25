import 'package:rudra_communication/rudra_communication.dart';

import '../../rudra_state.dart';

/// Application response containing composite Rudra state.
///
/// The state preserves concrete domain types, including
/// independently contributed workflow slices.
///
/// Verified absence of an unfinished workflow is represented
/// within the supplied state rather than by an absent response.
///
/// Construction alone does not establish journal authority
/// or authenticate the producer of the state.
///
/// Example:
/// ```dart
/// final response = StateReadResponse(state: state);
///
/// print(response.state.workflows.current_workflow?.version);
/// ```
final class StateReadResponse implements Response {
  /// Creates a State Read response containing [state].
  const StateReadResponse({required this.state});

  /// Composite application state associated with the request.
  final RudraState state;
}
