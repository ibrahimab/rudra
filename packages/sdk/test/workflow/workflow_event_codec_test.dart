import 'dart:convert';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_sdk/src/workflow/modules/lifecycle/serialization/workflow_start_serializer.dart';
import 'package:test/test.dart';

/// Verifies registry-driven, versioned workflow event serialization.
void main() {
  final codec = WorkflowEventCodec.standard();

  /// Supplies the original workflow bindings used in replay tests.
  WorkflowIdentity identity() => WorkflowIdentity(
    workflow_id: 'workflow-1',
    os_user_id: 'user-1',
    target_id: 'local-macos',
    root: TargetPath('/workspace/../downloads'),
  );

  test('round-trips all three lifecycle events', () {
    final events = <WorkflowEvent>[
      WorkflowStartEvent(
        target_id: 'local-macos',
        root: TargetPath('/workspace/../downloads'),
      ),
      WorkflowStartedEvent(identity: identity()),
      WorkflowEndedEvent(workflow_id: 'workflow-1'),
    ];

    final restored = <WorkflowEvent>[];

    for (final event in events) {
      final payload = codec.encode(event);

      expect(jsonDecode(payload)['schema_version'], 1);

      restored.add(
        codec.decode(event_type: event.event_type, payload_json: payload),
      );
    }

    expect(restored[0], isA<WorkflowStartEvent>());
    expect(restored[1], isA<WorkflowStartedEvent>());
    expect(restored[2], isA<WorkflowEndedEvent>());

    expect(
      (restored[0] as WorkflowStartEvent).root.value,
      '/workspace/../downloads',
    );

    expect((restored[1] as WorkflowStartedEvent).identity.os_user_id, 'user-1');

    expect((restored[2] as WorkflowEndedEvent).workflow_id, 'workflow-1');

    // Replayed instances must reproduce the same domain state.
    final state = WorkflowStateMachine().replay(restored);

    expect(state, isA<WorkflowEndedState>());
    expect(state.version, 3);
    expect(state.is_terminal, isTrue);
  });

  test('preserves the existing version 1 command representation', () {
    const old_payload =
        '{"schema_version":1,"target_id":"local-macos",'
        '"root":"/workspace"}';

    final restored = codec.decode(
      event_type: WorkflowStartEvent.type_id,
      payload_json: old_payload,
    );

    expect(restored, isA<WorkflowStartEvent>());
    expect((restored as WorkflowStartEvent).root.value, '/workspace');

    // Preserve canonical JSON for existing idempotency checks.
    expect(codec.encode(restored), old_payload);
  });

  test('uses latest version for writing and older versions for reading', () {
    final versioned_codec = WorkflowEventCodec(
      serializers: [
        const WorkflowStartSerializer(),
        const _WorkflowStartV2Serializer(),
      ],
    );

    final event = WorkflowStartEvent(
      target_id: 'local-macos',
      root: TargetPath('/workspace'),
    );

    final new_payload = versioned_codec.encode(event);

    expect(jsonDecode(new_payload), {
      'schema_version': 2,
      'target_id': 'local-macos',
      'root_path': '/workspace',
    });

    // Version 1 data remains readable after version 2
    // becomes the default writer.
    const old_payload =
        '{"schema_version":1,"target_id":"local-macos",'
        '"root":"/old-workspace"}';

    final restored = versioned_codec.decode(
      event_type: WorkflowStartEvent.type_id,
      payload_json: old_payload,
    );

    expect((restored as WorkflowStartEvent).root.value, '/old-workspace');
  });

  test('rejects duplicate serializer registrations', () {
    expect(
      () => WorkflowEventCodec(
        serializers: [
          const WorkflowStartSerializer(),
          const WorkflowStartSerializer(),
        ],
      ),
      throwsStateError,
    );
  });

  test('rejects unknown event types and schema versions', () {
    expect(
      () => codec.decode(
        event_type: 'workflow.unknown',
        payload_json: '{"schema_version":1}',
      ),
      throwsFormatException,
    );

    expect(
      () => codec.decode(
        event_type: WorkflowStartEvent.type_id,
        payload_json: '{"schema_version":999}',
      ),
      throwsFormatException,
    );
  });

  test('rejects invalid and malformed payloads', () {
    expect(
      () => codec.decode(
        event_type: WorkflowStartedEvent.type_id,
        payload_json: jsonEncode({
          'schema_version': 1,
          'workflow_id': 'workflow-1',
          'os_user_id': '',
          'target_id': 'local-macos',
          'root': '/workspace',
        }),
      ),
      throwsFormatException,
    );

    expect(
      () => codec.decode(
        event_type: WorkflowEndedEvent.type_id,
        payload_json: 'not-json',
      ),
      throwsFormatException,
    );
  });

  test('typed serializer rejects incompatible event instances', () {
    const serializer = WorkflowStartSerializer();

    final wrong_event = WorkflowEndedEvent(workflow_id: 'workflow-1');

    // The non-generic interface accepts WorkflowEvent,
    // but the typed implementation must still enforce
    // its own concrete event type at runtime.
    expect(() => serializer.encode_event(wrong_event), throwsArgumentError);

    // The serializer's concrete type remains available
    // to the registry without using dynamic.
    expect(serializer.dart_type, WorkflowStartEvent);
  });
}

/// Test-only version 2 encoding for WorkflowStartEvent.
///
/// Demonstrates adding a version without modifying the
/// central codec or the existing version 1 serializer.
final class _WorkflowStartV2Serializer
    extends WorkflowTypedEventSerializer<WorkflowStartEvent> {
  const _WorkflowStartV2Serializer();

  @override
  String get event_type => WorkflowStartEvent.type_id;

  @override
  int get schema_version => 2;

  @override
  Map<String, Object?> encode(WorkflowStartEvent event) => {
    'target_id': event.target_id,
    'root_path': event.root.value,
  };

  @override
  WorkflowStartEvent decode(Map<String, dynamic> payload) {
    final target_id = payload['target_id'];
    final root_path = payload['root_path'];

    if (target_id is! String || root_path is! String) {
      throw const FormatException('Invalid v2 workflow start payload.');
    }

    return WorkflowStartEvent(
      target_id: target_id,
      root: TargetPath(root_path),
    );
  }
}
