/// Domain data contributed to an established workflow snapshot.
///
/// Implementations must be immutable and owned by their
/// respective SDK domain feature.
///
/// A slice does not independently own workflow identity,
/// version, lifecycle, persistence or authorization.
///
/// Concrete implementations extend this base class.
/// They must not expose mutable collections or fields.
abstract base class WorkflowSlice {
  /// Constructs an immutable domain slice.
  const WorkflowSlice();
}

/// Stable, strongly typed identity of a workflow domain slice.
///
/// [T] identifies the concrete slice contract.
///
/// Keys are compared using their identifier and declared type.
/// The module registry must separately reject duplicate identifiers,
/// including collisions between different slice types.
///
/// A key does not own mutable state or perform persistence.
///
/// Example:
/// ```dart
/// final inspection_key =
///     WorkflowSliceKey<InspectionSlice>(
///       'rudra.workflow.inspection',
///     );
/// ```
final class WorkflowSliceKey<T extends WorkflowSlice> {
  /// Creates a typed slice key.
  ///
  /// [id] must be nonblank and should be namespaced by its owner.
  ///
  /// Throws [ArgumentError] for a blank identifier.
  WorkflowSliceKey(String id) : id = _require_id(id);

  /// Stable identifier of the registered domain slice.
  final String id;

  /// Concrete type required by this key.
  Type get slice_type => T;

  /// Validates a slice and returns it with its declared type.
  ///
  /// Throws [StateError] if [slice] does not satisfy [T].
  /// An invalid slice must never be silently treated as absent.
  ///
  /// This operation does not mutate the supplied slice.
  T require_type(WorkflowSlice slice) {
    if (slice is! T) {
      throw StateError(
        'Workflow slice $id requires $T, '
        'but received ${slice.runtimeType}.',
      );
    }

    return slice;
  }

  @override
  bool operator ==(Object other) =>
      other is WorkflowSliceKey<WorkflowSlice> &&
      other.id == id &&
      other.slice_type == slice_type;

  @override
  int get hashCode => Object.hash(id, slice_type);

  static String _require_id(String value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(
        value,
        'id',
        'Workflow slice identifier must not be blank.',
      );
    }

    return value;
  }
}
