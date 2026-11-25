import 'dart:convert';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_sdk/src/workflow/messaging/serialization/workflow_identity_codec.dart';
import 'package:test/test.dart';

/// Verifies immutable workflow identity representations.
void main() {
  const codec = WorkflowIdentityCodec();

  const valid_payload = <String, Object?>{
    'workflow_id': 'workflow-001',
    'os_user_id': 'user-001',
    'target_id': 'local-macos',
    'root': '/workspace',
  };

  test('round-trips every original workflow identity binding', () {
    final identity = WorkflowIdentity(
      workflow_id: 'workflow-001',
      os_user_id: 'user-001',
      target_id: 'local-macos',
      root: TargetPath('/workspace'),
    );

    final payload = codec.encode(identity);

    expect(payload, valid_payload);

    final restored = codec.decode(jsonDecode(jsonEncode(payload)));

    expect(restored.workflow_id, identity.workflow_id);
    expect(restored.os_user_id, identity.os_user_id);
    expect(restored.target_id, identity.target_id);
    expect(restored.root.value, identity.root.value);
  });

  test('preserves target-native paths and identifier spelling', () {
    final paths = [
      '/workspace/../example',
      r'C:\Users\example\AppData',
      r'\\server\share\directory',
      'relative/directory',
    ];

    for (final path in paths) {
      final identity = WorkflowIdentity(
        workflow_id: ' Workflow-001 ',
        os_user_id: ' User-001 ',
        target_id: ' Target-001 ',
        root: TargetPath(path),
      );

      final restored = codec.decode(codec.encode(identity));

      expect(restored.workflow_id, identity.workflow_id);
      expect(restored.os_user_id, identity.os_user_id);
      expect(restored.target_id, identity.target_id);
      expect(restored.root.value, path);
    }
  });

  test('rejects malformed identity representations', () {
    final invalid_payloads = <Object?>[
      null,
      [],
      'workflow-001',
      <String, Object?>{},
      {...valid_payload, 'unexpected': true},
      {...valid_payload, 'scope_id': 'untrusted-scope'},
      {
        'workflow_id': 'workflow-001',
        'os_user_id': 'user-001',
        'target_id': 'local-macos',
      },
    ];

    for (final payload in invalid_payloads) {
      expect(() => codec.decode(payload), throwsA(isA<FormatException>()));
    }
  });

  test('rejects invalid identifier representations and values', () {
    final fields = ['workflow_id', 'os_user_id', 'target_id'];

    final invalid_values = <Object?>[null, 42, '', ' ', '\t\n'];

    for (final field in fields) {
      for (final value in invalid_values) {
        expect(
          () => codec.decode({...valid_payload, field: value}),
          throwsA(isA<FormatException>()),
          reason: 'Invalid identity field: $field',
        );
      }
    }
  });

  test('rejects invalid target path representations', () {
    final invalid_paths = <Object?>[null, 42, '', '/workspace\u0000'];

    for (final path in invalid_paths) {
      expect(
        () => codec.decode({...valid_payload, 'root': path}),
        throwsA(isA<FormatException>()),
      );
    }
  });
}
