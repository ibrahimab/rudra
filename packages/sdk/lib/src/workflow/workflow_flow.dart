import 'transitions/workflow_ended_transition.dart';
import 'transitions/workflow_start_transition.dart';
import 'transitions/workflow_started_transition.dart';
import 'transitions/workflow_transition.dart';
import 'workflow_flow_exception.dart';

/// Immutable registry of legal workflow lifecycle transitions.
///
/// Every rule is indexed by the exact pair:
///
/// (source state type, trigger event type)
///
/// Registration order does not determine transition precedence.
/// There are no wildcard matches or inheritance-based fallbacks.
///
/// Duplicate state/event pairs are rejected during construction.
///
/// A flow is assembled explicitly from Dart transition definitions.
/// No reflection, filesystem discovery, mutable global registry,
/// or runtime registration is used.
///
/// Once constructed, the registry and its exposed rule list cannot
/// be modified.
///
/// [WorkflowFlow.standard] supplies Rudra's currently supported
/// workflow lifecycle.
///
/// Custom flows allow deterministic extension and isolated tests.
///
/// Example:
/// ```dart
/// final flow = WorkflowFlow.standard();
///
/// final rule = flow.transition_for(
///   state_type: WorkflowInitialState,
///   event_type: WorkflowStartEvent,
/// );
///
/// print(rule != null);
/// // true
/// ```
final class WorkflowFlow {
  /// Creates an immutable flow from explicit transition rules.
  ///
  /// The supplied list is defensively copied.
  ///
  /// Throws [WorkflowFlowException] if two transitions register
  /// the same exact source-state and trigger-event type pair.
  ///
  /// An empty flow is valid but cannot perform transitions.
  factory WorkflowFlow({
    required List<WorkflowTransitionDefinition> transitions,
  }) {
    final rules = List<WorkflowTransitionDefinition>.unmodifiable(transitions);

    final registry = <(Type, Type), WorkflowTransitionDefinition>{};
    final event_types = <Type>{};

    for (final rule in rules) {
      final key = (rule.source_state_type, rule.trigger_event_type);

      if (registry.containsKey(key)) {
        throw WorkflowFlowException(
          code: WorkflowFlowErrorCode.duplicate_transition,
          source_state_type: rule.source_state_type,
          trigger_event_type: rule.trigger_event_type,
          message:
              'More than one transition is registered '
              'for the same state and event types.',
        );
      }

      registry[key] = rule;
      event_types.add(rule.trigger_event_type);
    }

    return WorkflowFlow._(
      rules,
      Map<(Type, Type), WorkflowTransitionDefinition>.unmodifiable(registry),
      Set<Type>.unmodifiable(event_types),
    );
  }

  /// Creates Rudra's standard workflow lifecycle definition.
  ///
  /// New lifecycle transitions are introduced here by importing
  /// and explicitly registering their typed definitions.
  ///
  /// The ordering of these definitions has no effect on dispatch.
  factory WorkflowFlow.standard() {
    return WorkflowFlow(
      transitions: [
        workflow_start_transition(),
        workflow_started_transition(),
        workflow_ended_transition(),
      ],
    );
  }

  /// Stores already-validated immutable registry structures.
  WorkflowFlow._(this.transitions, this._registry, this._event_types);

  /// Immutable registered transition definitions.
  ///
  /// Consumers cannot add, remove, or replace registrations.
  final List<WorkflowTransitionDefinition> transitions;

  /// Exact state/event lookup table.
  final Map<(Type, Type), WorkflowTransitionDefinition> _registry;

  /// Event types recognized by at least one registered rule.
  final Set<Type> _event_types;

  /// Finds the uniquely registered rule for two exact Dart types.
  ///
  /// Returns null when this particular transition is not defined.
  ///
  /// No rule is chosen by registration order or subclass matching.
  WorkflowTransitionDefinition? transition_for({
    required Type state_type,
    required Type event_type,
  }) {
    return _registry[(state_type, event_type)];
  }

  /// Reports whether the flow recognizes an exact event type.
  ///
  /// Recognition does not imply that the event is valid from
  /// every state.
  ///
  /// Stable string event identifiers do not control dispatch.
  bool supports_event_type(Type event_type) {
    return _event_types.contains(event_type);
  }
}
