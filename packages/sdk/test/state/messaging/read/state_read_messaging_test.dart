import 'dart:convert';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import 'package:rudra_sdk/src/state/messaging/read/codecs/state_read_request_codec.dart';
import 'package:rudra_sdk/src/state/messaging/read/codecs/state_read_response_codec.dart';

import 'package:test/test.dart';

/// Verifies composite application state read messaging contracts.
void main() {
  const request_codec = StateReadRequestCodec();

  final runtime = WorkflowRuntime.standard();

  final response_codec = StateReadResponseCodec(runtime: runtime);

  final absent_state = RudraState(
    workflows: WorkflowsState(current_workflow: null),
  );

  final identity = WorkflowIdentity(
    workflow_id: 'workflow-001',
    os_user_id: 'user-001',
    target_id: 'local-macos',
    root: TargetPath('/workspace'),
  );

  final snapshot = WorkflowSnapshot(
    identity: identity,
    lifecycle: runtime.lifecycles['rudra.workflow.active']!,
    version: 1,
  );

  final established_state = RudraState(
    workflows: WorkflowsState(current_workflow: snapshot),
  );

  group('State Read request', () {
    test('declares its concrete response contract and wire identity', () {
      const request = StateReadRequest();

      expect(request, isA<Request<StateReadResponse>>());

      expect(request_codec.type_id, 'rudra.state.read.request.v1');
    });

    test('round-trips an empty application request payload', () {
      final payload = request_codec.encode(const StateReadRequest());

      expect(payload, isEmpty);

      final restored = request_codec.decode(jsonDecode(jsonEncode(payload)));

      expect(restored, isA<StateReadRequest>());
      expect(request_codec.encode(restored), payload);
    });

    test('rejects malformed or unexpected request arguments', () {
      final invalid_payloads = <Object?>[
        null,
        [],
        '',
        42,
        {'os_user_id': 'user-001'},
        {'scope_id': 'scope-001'},
        {'workflow_id': 'workflow-001'},
        {'unexpected': null},
      ];

      for (final payload in invalid_payloads) {
        expect(
          () => request_codec.decode(payload),
          throwsA(isA<FormatException>()),
        );
      }
    });
  });

  group('State Read response', () {
    test('declares its response contract and stable wire identity', () {
      final response = StateReadResponse(state: absent_state);

      expect(response, isA<Response>());

      expect(response_codec.type_id, 'rudra.state.read.response.v1');

      expect(response.state, same(absent_state));
    });

    test('round-trips explicitly absent workflow state', () {
      final response = StateReadResponse(state: absent_state);

      final payload = response_codec.encode(response);

      expect(payload, {
        'workflows': {'current_workflow': null},
      });

      final restored = response_codec.decode(jsonDecode(jsonEncode(payload)));

      expect(restored.state, isA<RudraState>());
      expect(restored.state.workflows.current_workflow, isNull);
    });

    test('round-trips an established workflow within application state', () {
      final response = StateReadResponse(state: established_state);

      final payload = response_codec.encode(response);

      expect(payload, {
        'workflows': {
          'current_workflow': {
            'identity': {
              'workflow_id': identity.workflow_id,
              'os_user_id': identity.os_user_id,
              'target_id': identity.target_id,
              'root': identity.root.value,
            },
            'version': 1,
            'lifecycle': 'rudra.workflow.active',
            'slices': [],
          },
        },
      });

      final restored = response_codec.decode(jsonDecode(jsonEncode(payload)));

      final current = restored.state.workflows.current_workflow!;

      expect(current.identity.workflow_id, identity.workflow_id);
      expect(current.identity.os_user_id, identity.os_user_id);
      expect(current.identity.target_id, identity.target_id);
      expect(current.identity.root.value, identity.root.value);

      expect(current.version, 1);

      expect(
        current.lifecycle,
        same(runtime.lifecycles['rudra.workflow.active']),
      );

      expect(response_codec.encode(restored), payload);
    });

    test('propagates malformed application-state decoding failures', () {
      final invalid_payloads = <Object?>[
        null,
        [],
        <String, Object?>{},
        {'workflows': null},
        {
          'workflows': {'unexpected': null},
        },
        {
          'workflows': {
            'current_workflow': {'invalid': true},
          },
        },
        {
          'workflows': {'current_workflow': null},
          'unexpected': null,
        },
      ];

      for (final payload in invalid_payloads) {
        expect(
          () => response_codec.decode(payload),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('propagates incompatible application-state encoding failures', () {
      final invalid_snapshot = WorkflowSnapshot(
        identity: identity,
        lifecycle: WorkflowLifecycle(
          id: 'test.unregistered',
          is_terminal: false,
        ),
        version: 1,
      );

      final response = StateReadResponse(
        state: RudraState(
          workflows: WorkflowsState(current_workflow: invalid_snapshot),
        ),
      );

      expect(() => response_codec.encode(response), throwsStateError);
    });
  });
}
