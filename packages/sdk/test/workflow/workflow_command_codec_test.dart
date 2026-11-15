import 'dart:convert';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies portable and versioned workflow command serialization.
void main() {
  const codec = WorkflowCommandCodec();

  test('preserves workflow start bindings across serialization', () {
    final original = WorkflowStartEvent(
      target_id: 'local-macos',
      root: TargetPath('/workspace/../downloads'),
    );

    final payload = codec.encode(original);

    expect(jsonDecode(payload), {
      'schema_version': WorkflowCommandCodec.schema_version,
      'target_id': 'local-macos',
      'root': '/workspace/../downloads',
    });

    final restored = codec.decode(
      event_type: original.event_type,
      payload_json: payload,
    );

    expect(restored, isA<WorkflowStartEvent>());

    final start = restored as WorkflowStartEvent;

    expect(start.target_id, original.target_id);
    expect(start.root.value, original.root.value);
  });

  test('rejects unknown schema versions', () {
    expect(
      () => codec.decode(
        event_type: WorkflowStartEvent.type_id,
        payload_json: jsonEncode({
          'schema_version': 999,
          'target_id': 'local-macos',
          'root': '/workspace',
        }),
      ),
      throwsFormatException,
    );
  });

  test('rejects unsupported command types', () {
    expect(
      () => codec.decode(
        event_type: 'workflow.unknown',
        payload_json: jsonEncode({
          'schema_version': WorkflowCommandCodec.schema_version,
        }),
      ),
      throwsFormatException,
    );
  });
}
