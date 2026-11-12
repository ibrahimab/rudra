/// Immutable state derived from committed workflow events.
///
/// Concrete states describe the current lifecycle phase.
///
/// Every state exposes the number of committed events applied
/// through [version].
///
/// State construction alone does not commit an event.
///
/// Implementations must be immutable and retain all established
/// workflow bindings relevant to subsequent transitions.
///
/// Example:
/// ```dart
/// final WorkflowState state = WorkflowInitialState();
///
/// print(state.version);
/// // 0
/// ```
abstract base class WorkflowState {
  /// Creates a workflow state without performing I/O.
  const WorkflowState();

  /// Number of committed events applied to produce this state.
  ///
  /// The initial state has version zero.
  /// Each successful transition must increase the version by one.
  int get version;

  /// Whether this state permanently terminates its workflow.
  ///
  /// Terminal states cannot accept further workflow transitions,
  /// even if a malformed flow registers an outgoing rule.
  ///
  /// New terminal state implementations override this getter.
  bool get is_terminal => false;

  /// Validates the version of an event-derived state.
  ///
  /// The initial state uses version zero separately.
  ///
  /// Throws [ArgumentError] for zero or negative versions.
  static int require_positive_version(int version) {
    if (version <= 0) {
      throw ArgumentError.value(
        version,
        'version',
        'An event-derived state requires a positive version.',
      );
    }

    return version;
  }
}
