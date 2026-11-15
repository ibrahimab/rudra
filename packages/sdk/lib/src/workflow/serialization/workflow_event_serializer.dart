import '../events/workflow_event.dart';

/// Defines versioned serialization for one concrete workflow event.
///
/// Serializers own the event-specific payload representation.
/// JSON encoding, version dispatch, and serializer registration
/// are handled separately by WorkflowEventCodec.
///
/// Different schema versions of the same event may have
/// separate serializer implementations.
///
/// E identifies the concrete domain event handled.
abstract base class WorkflowEventSerializer<E extends WorkflowEvent> {
  /// Creates a stateless event serializer.
  const WorkflowEventSerializer();

  /// Concrete Dart event type supported by this serializer.
  Type get dart_type => E;

  /// Stable persisted event type identifier.
  String get event_type;

  /// Persisted payload schema version supported.
  int get schema_version;

  /// Converts a typed event into event-specific payload fields.
  ///
  /// The returned map must not contain 'schema_version'.
  Map<String, Object?> encode(E event);

  /// Reconstructs a typed event from versioned payload fields.
  ///
  /// Invalid persisted data must result in FormatException.
  E decode(Map<String, dynamic> payload);

  /// Safely encodes an event selected by the runtime registry.
  ///
  /// Exact type matching prevents serializers from accepting
  /// unrelated subclasses or incompatible event instances.
  Map<String, Object?> encode_event(WorkflowEvent event) {
    if (event.runtimeType != E) {
      throw ArgumentError.value(event, 'event', 'Expected event type $E.');
    }

    return encode(event as E);
  }
}
