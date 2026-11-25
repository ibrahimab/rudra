import 'package:rudra_communication/rudra_communication.dart';

import 'state_read_response.dart';

/// Requests the current composite Rudra application state.
///
/// The trusted host determines the application scope associated
/// with the requesting communication peer.
///
/// The request carries no caller-supplied ownership or
/// persistence scope information.
///
/// Example:
/// ```dart
/// final response = await session.request(
///   const StateReadRequest(),
/// );
///
/// final current = response.state.workflows.current_workflow;
/// ```
final class StateReadRequest implements Request<StateReadResponse> {
  /// Creates a request for the current composite application state.
  const StateReadRequest();
}
