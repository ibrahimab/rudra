import '../events/workflow_event.dart';

/// Non-generic serialization contract for workflow events.
///
/// The registry and central codec depend on this interface
/// without knowing the concrete event type.
///
/// Implementations identify their supported event type and
/// persisted schema version.
///
/// Event-specific payload encoding and decoding are delegated
/// through [encode_event] and [decode_event].
abstract interface class WorkflowEventSerializer {
  /// Concrete Dart event type handled by this serializer.
  Type get dart_type;

  /// Stable persisted event type identifier.
  String get event_type;

  /// Supported payload schema version.
  int get schema_version;

  /// Converts a workflow event to its persisted payload fields.
  ///
  /// The caller must not supply an incompatible event type.
  /// Implementations must reject incompatible event instances.
  ///
  /// The returned map must not contain 'schema_version'.
  Map<String, Object?> encode_event(WorkflowEvent event);

  /// Reconstructs an event from persisted payload fields.
  ///
  /// Implementations must reject malformed event data.
  WorkflowEvent decode_event(Map<String, dynamic> payload);
}

/// Strongly typed base implementation of event serialization.
///
/// E is the concrete domain event type.
///
/// This class bridges the non-generic registry contract
/// to strongly typed event-specific encoding and decoding.
///
/// The registry never needs to reference E or use dynamic.
///
/// Example:
/// ```dart
/// final class MySerializer
///     extends WorkflowTypedEventSerializer<MyEvent> {
///   // Implement encode(), decode(), and event metadata.
/// }
/// ```
abstract base class WorkflowTypedEventSerializer<E extends WorkflowEvent>
    implements WorkflowEventSerializer {
  /// Creates a stateless typed serializer.
  const WorkflowTypedEventSerializer();

  /// Exposes the concrete generic type to the registry.
  @override
  Type get dart_type => E;

  /// Event-specific serialization into persistence fields.
  ///
  /// Implementations only accept their declared event type.
  Map<String, Object?> encode(E event);

  /// Event-specific reconstruction from persistence fields.
  ///
  /// Invalid persisted data must throw FormatException.
  E decode(Map<String, dynamic> payload);

  /// Bridges an untyped registry call to typed serialization.
  ///
  /// Validates the exact runtime event type before invoking
  /// the event-specific encode method.
  @override
  Map<String, Object?> encode_event(WorkflowEvent event) {
    // A registry-selected serializer must not accidentally
    // encode an event belonging to another concrete type.
    if (event.runtimeType != E) {
      throw ArgumentError.value(event, 'event', 'Expected event type $E.');
    }

    // The validated cast restores the concrete event type
    // expected by the serializer implementation.
    return encode(event as E);
  }

  /// Bridges persisted data to typed event reconstruction.
  ///
  /// The central codec verifies that the resulting event
  /// matches the serializer's registered event identity.
  @override
  WorkflowEvent decode_event(Map<String, dynamic> payload) {
    return decode(payload);
  }
}
