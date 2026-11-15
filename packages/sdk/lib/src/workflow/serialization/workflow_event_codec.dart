import 'dart:convert';

import '../events/workflow_event.dart';
import '../modules/standard_workflow_modules.dart';
import '../modules/workflow_module_registry.dart';

import 'workflow_event_serializer.dart';

/// Registry-driven, versioned serialization of workflow events.
///
/// Event-specific encoding and decoding belong to registered
/// WorkflowEventSerializer implementations.
///
/// The codec owns JSON envelopes, schema version dispatch,
/// and selection of the newest serializer for writing.
///
/// Historical serializers remain available for replay.
final class WorkflowEventCodec {
  /// Builds a codec from explicit serializer contributions.
  ///
  /// Rejects duplicate version registrations and inconsistent
  /// mappings between stable event IDs and Dart event types.
  factory WorkflowEventCodec({
    required Iterable<WorkflowEventSerializer<dynamic>> serializers,
  }) {
    final readers = <(String, int), WorkflowEventSerializer<dynamic>>{};

    final writers = <Type, WorkflowEventSerializer<dynamic>>{};

    final known_types = <String, Type>{};
    final known_ids = <Type, String>{};

    for (final serializer in serializers) {
      final event_type = serializer.event_type;
      final dart_type = serializer.dart_type;
      final version = serializer.schema_version;

      if (event_type.trim().isEmpty || version <= 0) {
        throw ArgumentError(
          'Event serializers require a nonblank event type '
          'and a positive schema version.',
        );
      }

      if (known_types.containsKey(event_type) &&
          known_types[event_type] != dart_type) {
        throw StateError('Conflicting Dart types for event ID: $event_type');
      }

      if (known_ids.containsKey(dart_type) &&
          known_ids[dart_type] != event_type) {
        throw StateError('Conflicting event IDs for Dart type: $dart_type');
      }

      final key = (event_type, version);

      if (readers.containsKey(key)) {
        throw StateError('Duplicate event serializer: $key');
      }

      readers[key] = serializer;
      known_types[event_type] = dart_type;
      known_ids[dart_type] = event_type;

      // New events use the highest registered schema version.
      // Older versions remain available for decoding.
      final current_writer = writers[dart_type];

      if (current_writer == null || version > current_writer.schema_version) {
        writers[dart_type] = serializer;
      }
    }

    return WorkflowEventCodec._(
      Map.unmodifiable(readers),
      Map.unmodifiable(writers),
    );
  }

  /// Builds a codec from an existing module registry.
  ///
  /// The serializer registrations are snapshotted.
  factory WorkflowEventCodec.from_registry(WorkflowModuleRegistry registry) {
    return WorkflowEventCodec(serializers: registry.serializers);
  }

  /// Builds a codec using Rudra's standard workflow modules.
  ///
  /// Adding an event to a module does not require changing
  /// this constructor or any central event-type switch.
  factory WorkflowEventCodec.standard() {
    final registry = WorkflowModuleRegistry();

    for (final module in standard_workflow_modules()) {
      registry.register(module);
    }

    return WorkflowEventCodec.from_registry(registry);
  }

  /// Stores validated, immutable serializer lookup tables.
  WorkflowEventCodec._(this._readers, this._writers);

  /// Read strategies indexed by event ID and schema version.
  final Map<(String, int), WorkflowEventSerializer<dynamic>> _readers;

  /// Latest write strategy indexed by concrete Dart type.
  final Map<Type, WorkflowEventSerializer<dynamic>> _writers;

  /// Serializes a supported workflow event into versioned JSON.
  ///
  /// Dispatch uses the concrete Dart type, not an untrusted
  /// string supplied by the event implementation.
  String encode(WorkflowEvent event) {
    final serializer = _writers[event.runtimeType];

    if (serializer == null) {
      throw UnsupportedError(
        'No serializer registered for ${event.runtimeType}.',
      );
    }

    if (serializer.event_type != event.event_type) {
      throw StateError('Event type does not match its registered serializer.');
    }

    final fields = serializer.encode_event(event);

    // The codec, not an event-specific strategy, owns
    // the persisted schema-version envelope.
    if (fields.containsKey('schema_version')) {
      throw StateError('Event serializer cannot override schema_version.');
    }

    return jsonEncode(<String, Object?>{
      'schema_version': serializer.schema_version,
      ...fields,
    });
  }

  /// Reconstructs a workflow event from its persisted payload.
  ///
  /// Dispatch requires both the stable event type and the
  /// exact stored schema version.
  ///
  /// Unknown types, unsupported versions, and incompatible
  /// decoded event instances produce FormatException.
  WorkflowEvent decode({
    required String event_type,
    required String payload_json,
  }) {
    final payload = jsonDecode(payload_json);

    if (payload is! Map<String, dynamic>) {
      throw const FormatException('Invalid workflow event payload.');
    }

    final version = payload['schema_version'];

    if (version is! int || version <= 0) {
      throw const FormatException('Invalid workflow event schema version.');
    }

    final serializer = _readers[(event_type, version)];

    if (serializer == null) {
      throw FormatException(
        'Unsupported workflow event or schema version: '
        '$event_type / $version',
      );
    }

    final WorkflowEvent event = serializer.decode(payload);

    // A serializer must reconstruct precisely the event
    // type declared by its registration.
    if (event.runtimeType != serializer.dart_type ||
        event.event_type != event_type) {
      throw const FormatException(
        'Decoded event does not match its registered type.',
      );
    }

    return event;
  }
}
