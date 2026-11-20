import '../workflow_identity.dart';
import 'workflow_lifecycle.dart';
import 'workflow_slice.dart';

/// Immutable composite state of an established workflow.
///
/// Every snapshot contains the original [identity], a positive
/// committed event [version], and a mandatory [lifecycle].
///
/// Feature-owned domain state is stored as typed slice bindings.
/// The collection is copied and validated during construction,
/// preventing later changes to its input from affecting the snapshot.
///
/// A snapshot represents one coherent workflow version. Its
/// construction alone does not establish authoritative state.
/// Authority is established by validating committed journal events
/// through the SDK workflow state machine.
///
/// All established workflow identities and original bindings must
/// remain unchanged across subsequent versions. The state machine
/// is responsible for enforcing those transition invariants.
///
/// Example:
/// ```dart
/// final snapshot = WorkflowSnapshot(
///   identity: identity,
///   version: 1,
///   lifecycle: active_lifecycle,
/// );
///
/// print(snapshot.identity.workflow_id);
/// print(snapshot.version);
/// ```
final class WorkflowSnapshot {
  /// Constructs an immutable established-workflow snapshot.
  ///
  /// [identity] provides the workflow's immutable identity and
  /// original filesystem bindings.
  ///
  /// [version] identifies the committed workflow-local event
  /// position and must be positive.
  ///
  /// [lifecycle] identifies the current domain lifecycle phase.
  ///
  /// [slices] supplies independently owned domain values.
  /// Every slice identifier and concrete type must be unique.
  /// The supplied collection is defensively copied.
  ///
  /// Throws [ArgumentError] for a nonpositive version.
  ///
  /// Throws [StateError] for duplicate slice identifiers,
  /// duplicate concrete slice types, or incompatible values.
  ///
  /// Registration and authorization checks remain the
  /// responsibility of the workflow state machine.
  WorkflowSnapshot({
    required this.identity,
    required this.lifecycle,
    required int version,
    Iterable<WorkflowSliceBinding<WorkflowSlice>> slices = const [],
  }) : version = _require_version(version),
       _slice_bindings = _index_slices(slices);

  /// Identity and original bindings of the established workflow.
  ///
  /// These values must remain unchanged across all versions.
  final WorkflowIdentity identity;

  /// Committed event position within this workflow's journal.
  ///
  /// Each successful committed domain-event transition advances
  /// this value exactly once.
  final int version;

  /// Registered lifecycle phase of this workflow version.
  ///
  /// Lifecycle transitions are validated by the SDK state machine.
  final WorkflowLifecycle lifecycle;

  /// Domain slices indexed by their stable registered identifiers.
  ///
  /// The map is immutable and contains no duplicate slice types.
  final Map<String, WorkflowSliceBinding<WorkflowSlice>> _slice_bindings;

  /// Whether the workflow has permanently reached a terminal phase.
  ///
  /// Terminal workflows cannot accept further domain transitions.
  /// The state machine enforces this invariant during processing.
  bool get is_terminal => lifecycle.is_terminal;

  /// Returns the immutable bindings contained in this snapshot.
  ///
  /// The returned iterable exposes the snapshot's validated bindings
  /// without exposing its internal map for modification.
  ///
  /// A state transition can use these bindings to retain unchanged
  /// feature-owned slices when constructing the next snapshot.
  Iterable<WorkflowSliceBinding<WorkflowSlice>> get slice_bindings =>
      _slice_bindings.values;

  /// Retrieves the domain slice associated with [key].
  ///
  /// Returns the concrete [T] value when the slice is present,
  /// or `null` when the snapshot contains no such slice.
  ///
  /// Throws [StateError] if the identifier exists but its
  /// registered concrete type differs from the requested key.
  /// A type mismatch is never treated as an absent slice.
  ///
  /// Reading a slice never modifies the snapshot.
  T? slice<T extends WorkflowSlice>(WorkflowSliceKey<T> key) {
    final binding = _slice_bindings[key.id];

    if (binding == null) {
      return null;
    }

    if (binding.key.slice_type != key.slice_type) {
      throw StateError(
        'Workflow slice ${key.id} has type '
        '${binding.key.slice_type}, not ${key.slice_type}.',
      );
    }

    return key.require_type(binding.value);
  }

  /// Validates the committed version of an established workflow.
  ///
  /// Version zero represents no established workflow and cannot
  /// be used to construct a [WorkflowSnapshot].
  ///
  /// Throws [ArgumentError] for nonpositive versions.
  static int _require_version(int version) {
    if (version <= 0) {
      throw ArgumentError.value(
        version,
        'version',
        'An established workflow requires a positive version.',
      );
    }

    return version;
  }

  /// Validates and freezes independently contributed slice bindings.
  ///
  /// Duplicate identifiers are rejected even when the associated
  /// Dart types differ. Duplicate concrete types are rejected
  /// even when their identifiers differ.
  ///
  /// The resulting map is constructed only after every binding
  /// has passed validation.
  static Map<String, WorkflowSliceBinding<WorkflowSlice>> _index_slices(
    Iterable<WorkflowSliceBinding<WorkflowSlice>> slices,
  ) {
    final bindings = <String, WorkflowSliceBinding<WorkflowSlice>>{};
    final registered_types = <Type>{};

    for (final binding in slices) {
      final key = binding.key;

      // Revalidate through the declared key before accepting a
      // value supplied through a heterogeneous collection.
      key.require_type(binding.value);

      if (bindings.containsKey(key.id)) {
        throw StateError('Duplicate workflow slice identifier: ${key.id}');
      }

      if (!registered_types.add(key.slice_type)) {
        throw StateError('Duplicate workflow slice type: ${key.slice_type}');
      }

      bindings[key.id] = binding;
    }

    return Map.unmodifiable(bindings);
  }
}
