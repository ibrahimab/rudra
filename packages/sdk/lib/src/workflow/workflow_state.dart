import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import 'workflow_identity.dart';

/// Immutable state produced by applying committed workflow events.
///
/// The concrete state type describes the lifecycle phase.
///
/// Every state exposes the number of committed events applied
/// through [version].
///
/// Version zero represents the initial state before any event.
///
/// State instances contain no filesystem handles, persistence
/// connections, application controllers, or mutable collections.
///
/// The workflow state machine owns legal state transitions.
/// Constructing a state directly does not commit domain events.
sealed class WorkflowState {
  /// Initializes a workflow state.
  const WorkflowState();

  /// Number of committed events applied to derive this state.
  ///
  /// This value increases monotonically as events are applied.
  int get version;
}

/// State before any workflow-start request has been applied.
///
/// No workflow identity or original bindings have been established.
///
/// Example:
/// ```dart
/// final state = WorkflowInitialState();
/// print(state.version);
/// // 0
/// ```
final class WorkflowInitialState extends WorkflowState {
  /// Creates the initial state.
  const WorkflowInitialState();

  @override
  int get version => 0;
}

/// State after receiving a workflow-start request.
///
/// The request has been recorded, but workflow creation has not
/// yet been established.
///
/// This state deliberately has no [WorkflowIdentity].
///
/// The requested target and root are retained for validation
/// against a subsequent successful outcome.
final class WorkflowStartRequestedState extends WorkflowState {
  /// Creates the state representing a recorded start request.
  ///
  /// [version] must be positive.
  ///
  /// Throws [ArgumentError] for a blank target identifier or
  /// a nonpositive version.
  WorkflowStartRequestedState({
    required String target_id,
    required this.root,
    required int version,
  })  : target_id = _require_target_id(target_id),
        version = _require_positive_version(version);

  /// Target specified in the original start request.
  final String target_id;

  /// Root specified in the original start request.
  final TargetPath root;

  @override
  final int version;

  /// Validates the configured filesystem target identifier.
  static String _require_target_id(String value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(
        value,
        'target_id',
        'The target identifier must not be blank.',
      );
    }

    return value;
  }
}

/// State of a successfully established, unfinished workflow.
///
/// [identity] contains the original authoritative workflow
/// bindings, which must remain unchanged in subsequent states.
final class WorkflowActiveState extends WorkflowState {
  /// Creates an active workflow state.
  ///
  /// [version] must be positive.
  ///
  /// Throws [ArgumentError] for a nonpositive version.
  WorkflowActiveState({
    required this.identity,
    required int version,
  }) : version = _require_positive_version(version);

  /// Established workflow identity and original bindings.
  final WorkflowIdentity identity;

  @override
  final int version;
}

/// Terminal state of a workflow.
///
/// The original identity remains available after the workflow
/// has ended, preserving its association with historical events.
///
/// This state cannot transition further under the initial
/// three-event lifecycle.
final class WorkflowEndedState extends WorkflowState {
  /// Creates a terminal workflow state.
  ///
  /// [version] must be positive.
  ///
  /// Throws [ArgumentError] for a nonpositive version.
  WorkflowEndedState({
    required this.identity,
    required int version,
  }) : version = _require_positive_version(version);

  /// Original workflow identity and bindings.
  final WorkflowIdentity identity;

  @override
  final int version;
}

/// Validates an event-derived stream version.
///
/// Positive versions represent states derived from committed
/// events. The initial state uses version zero separately.
int _require_positive_version(int version) {
  if (version <= 0) {
    throw ArgumentError.value(
      version,
      'version',
      'An event-derived state requires a positive version.',
    );
  }

  return version;
}
