/// Immutable identity and terminality of a workflow lifecycle phase.
///
/// Lifecycle values are contributed by SDK workflow modules.
/// No central enumeration needs to change when a feature
/// introduces a new phase.
///
/// A lifecycle value is not authorization to perform an operation.
/// The workflow state machine validates lifecycle transitions
/// against the registered workflow runtime.
///
/// Two values are equal when their identifiers and terminality
/// agree. Registration must reject conflicting definitions
/// sharing the same identifier.
final class WorkflowLifecycle {
  /// Creates a lifecycle value with a stable identifier.
  ///
  /// [id] must not be blank and should be namespaced by its owner.
  /// [is_terminal] indicates whether further domain transitions
  /// are permanently forbidden.
  ///
  /// Throws [ArgumentError] for a blank identifier.
  WorkflowLifecycle({required String id, required this.is_terminal})
    : id = _require_id(id);

  /// Stable, module-owned lifecycle identifier.
  final String id;

  /// Whether the lifecycle permanently forbids further transitions.
  final bool is_terminal;

  @override
  bool operator ==(Object other) =>
      other is WorkflowLifecycle &&
      other.id == id &&
      other.is_terminal == is_terminal;

  @override
  int get hashCode => Object.hash(id, is_terminal);

  static String _require_id(String value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(
        value,
        'id',
        'Lifecycle identifier must not be blank.',
      );
    }

    return value;
  }
}
