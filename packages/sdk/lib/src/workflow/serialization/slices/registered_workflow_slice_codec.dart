import '../../states/workflow_slice.dart';

import 'workflow_slice_codec.dart';

/// Retains a feature-owned slice codec behind a validated
/// heterogeneous registration boundary.
///
/// [T] preserves the concrete relationship between the codec,
/// its slice identity and reconstructed domain values.
///
/// The registration captures stable codec metadata and validates
/// exact concrete types before crossing the serialization boundary.
///
/// Example:
/// ```dart
/// final registered = RegisteredWorkflowSliceCodec(
///   codec: const InspectionSliceCodec(),
/// );
///
/// final binding = registered.decode_binding(payload);
/// ```
final class RegisteredWorkflowSliceCodec<T extends WorkflowSlice> {
  /// Creates a validated registration for [codec].
  ///
  /// Captures its declared key and schema version without
  /// invoking serialization.
  ///
  /// Throws [ArgumentError] for a nonpositive schema version.
  ///
  /// Throws [StateError] if the key does not identify the
  /// exact concrete type declared by this registration.
  RegisteredWorkflowSliceCodec({required WorkflowSliceCodec<T> codec})
    : _codec = codec,
      key = codec.key,
      schema_version = codec.schema_version {
    if (schema_version <= 0) {
      throw ArgumentError.value(
        schema_version,
        'schema_version',
        'Workflow slice schema version must be positive.',
      );
    }

    if (T == WorkflowSlice || key.slice_type != T) {
      throw StateError(
        'Workflow slice codec ${key.id} requires '
        'an exact concrete slice type.',
      );
    }
  }

  /// Feature-owned typed serialization implementation.
  final WorkflowSliceCodec<T> _codec;

  /// Captured stable identity of the registered slice.
  final WorkflowSliceKey<T> key;

  /// Captured schema version supported by the registered codec.
  final int schema_version;

  /// Serializes the domain value contained in [binding].
  ///
  /// Returns the feature-owned structured payload.
  ///
  /// Throws [StateError] if the binding has an incompatible
  /// identity or concrete value type.
  ///
  /// Serialization failures from the feature codec propagate.
  Object? encode_binding(WorkflowSliceBinding<WorkflowSlice> binding) {
    if (binding.key != key || binding.value.runtimeType != key.slice_type) {
      throw StateError('Incompatible workflow slice binding for ${key.id}.');
    }

    return _codec.encode(key.require_type(binding.value));
  }

  /// Reconstructs a concrete typed slice binding from [payload].
  ///
  /// Returns a binding preserving the registered slice key and
  /// the concrete type [T].
  ///
  /// Throws [FormatException] for malformed feature payloads.
  ///
  /// Throws [StateError] if the codec returns a value whose
  /// concrete type violates the registered contract.
  WorkflowSliceBinding<T> decode_binding(Object? payload) {
    final value = _codec.decode(payload);

    // Subtype compatibility alone is insufficient because
    // registrations identify exact concrete domain contracts.
    if (value.runtimeType != key.slice_type) {
      throw StateError(
        'Workflow slice codec ${key.id} returned '
        '${value.runtimeType} instead of ${key.slice_type}.',
      );
    }

    return WorkflowSliceBinding<T>(key: key, value: value);
  }
}
