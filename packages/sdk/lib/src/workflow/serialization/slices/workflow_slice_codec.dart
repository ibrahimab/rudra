import '../../states/workflow_slice.dart';

/// Serialization contract owned by a workflow domain-slice feature.
///
/// [T] identifies the concrete immutable slice represented by
/// this codec.
///
/// The stable slice identity belongs to the domain feature.
/// The schema version identifies the codec's payload representation
/// independently of workflow versions and event serialization.
///
/// Implementations must be immutable, deterministic and free
/// of persistence, filesystem and communication side effects.
///
/// Example:
/// ```dart
/// final class InspectionSliceCodec
///     implements WorkflowSliceCodec<InspectionSlice> {
///   const InspectionSliceCodec();
///
///   @override
///   WorkflowSliceKey<InspectionSlice> get key =>
///       InspectionSlice.key;
///
///   @override
///   int get schema_version => 1;
///
///   @override
///   Object? encode(InspectionSlice slice) =>
///       {'count': slice.count};
///
///   @override
///   InspectionSlice decode(Object? payload) {
///     if (payload is! Map<String, Object?> ||
///         payload.length != 1 ||
///         payload['count'] is! int) {
///       throw const FormatException(
///         'Invalid inspection slice payload.',
///       );
///     }
///
///     return InspectionSlice(
///       count: payload['count'] as int,
///     );
///   }
/// }
/// ```
abstract interface class WorkflowSliceCodec<T extends WorkflowSlice> {
  /// Stable typed identity of the represented domain slice.
  WorkflowSliceKey<T> get key;

  /// Positive schema version of the supported payload representation.
  int get schema_version;

  /// Converts [slice] into its structured payload representation.
  ///
  /// Returns a JSON-compatible value preserving the slice's
  /// domain data.
  ///
  /// Implementations must produce deterministic representations
  /// for equivalent slice values.
  Object? encode(T slice);

  /// Reconstructs the concrete domain slice from [payload].
  ///
  /// Returns an immutable value of the exact registered slice type.
  ///
  /// Throws [FormatException] for malformed or unsupported payloads.
  T decode(Object? payload);
}
