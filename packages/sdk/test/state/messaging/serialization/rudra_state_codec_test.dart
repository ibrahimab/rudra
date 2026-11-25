import 'dart:convert';

import 'package:rudra_sdk/rudra_sdk.dart';

import 'package:rudra_sdk/src/state/messaging/serialization/rudra_state_codec.dart';
import 'package:rudra_sdk/src/workflow/messaging/serialization/workflows_state_codec.dart';

import 'package:test/test.dart';

import '../../../workflow/messaging/fixtures/serialization_features.dart';

/// Verifies serialization of owner-scoped workflow collections
/// and complete composite Rudra application state.
void main() {
  final host_runtime = create_serialization_runtime(
    features: [const CounterFeatureModule(), const FindingsFeatureModule()],
  );

  final client_runtime = create_serialization_runtime(
    features: [const FindingsFeatureModule(), const CounterFeatureModule()],
  );

  final workflows_codec = WorkflowsStateCodec(runtime: host_runtime);

  final host_codec = RudraStateCodec(runtime: host_runtime);

  final client_codec = RudraStateCodec(runtime: client_runtime);

  final identity = WorkflowIdentity(
    workflow_id: 'workflow-001',
    os_user_id: 'user-001',
    target_id: 'local-macos',
    root: TargetPath('/workspace'),
  );

  final snapshot = WorkflowSnapshot(
    identity: identity,
    lifecycle: host_runtime.lifecycles[CounterFeatureModule.lifecycle_id]!,
    version: 12,
    slices: [
      WorkflowSliceBinding<CounterSlice>(
        key: CounterSlice.key,
        value: const CounterSlice(42),
      ),
      WorkflowSliceBinding<FindingsSlice>(
        key: FindingsSlice.key,
        value: const FindingsSlice('Obsolete SDK'),
      ),
    ],
  );

  final state = RudraState(
    workflows: WorkflowsState(current_workflow: snapshot),
  );

  final absent_state = RudraState(
    workflows: WorkflowsState(current_workflow: null),
  );

  const absent_payload = <String, Object?>{
    'workflows': {'current_workflow': null},
  };

  group('workflow collection serialization', () {
    test('round-trips an explicitly absent current workflow', () {
      final workflows = WorkflowsState(current_workflow: null);

      final payload = workflows_codec.encode(workflows);

      expect(payload, {'current_workflow': null});

      final restored = workflows_codec.decode(payload);

      expect(restored.current_workflow, isNull);
    });

    test('round-trips an established nonterminal workflow', () {
      final payload = workflows_codec.encode(state.workflows);
      final restored = workflows_codec.decode(payload);

      expect(restored.current_workflow, isNotNull);

      expect(
        restored.current_workflow!.identity.workflow_id,
        identity.workflow_id,
      );

      expect(restored.current_workflow!.version, snapshot.version);

      expect(restored.current_workflow!.is_terminal, isFalse);
    });

    test('rejects missing or malformed current-workflow selectors', () {
      final invalid_payloads = <Object?>[
        null,
        [],
        <String, Object?>{},
        {'unexpected': null},
        {'current_workflow': true},
        {'current_workflow': <String, Object?>{}},
        {'current_workflow': null, 'unexpected': true},
      ];

      for (final payload in invalid_payloads) {
        expect(
          () => workflows_codec.decode(payload),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('rejects terminal snapshots as current unfinished workflows', () {
      final encoded = workflows_codec.encode(state.workflows);

      final current = encoded['current_workflow'] as Map<String, Object?>;

      expect(
        () => workflows_codec.decode({
          'current_workflow': {...current, 'lifecycle': 'rudra.workflow.ended'},
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('composite application state serialization', () {
    test('round-trips verified absence through the complete hierarchy', () {
      final payload = host_codec.encode(absent_state);

      expect(payload, absent_payload);

      final restored = client_codec.decode(jsonDecode(jsonEncode(payload)));

      expect(restored.workflows, isA<WorkflowsState>());
      expect(restored.workflows.current_workflow, isNull);
    });

    test(
      'reconstructs concrete application state across independent runtimes',
      () {
        final payload = host_codec.encode(state);

        final restored = client_codec.decode(jsonDecode(jsonEncode(payload)));

        expect(restored, isA<RudraState>());
        expect(restored.workflows, isA<WorkflowsState>());

        final workflow = restored.workflows.current_workflow!;

        expect(workflow.identity.workflow_id, identity.workflow_id);
        expect(workflow.identity.os_user_id, identity.os_user_id);
        expect(workflow.identity.target_id, identity.target_id);
        expect(workflow.identity.root.value, identity.root.value);

        expect(workflow.version, snapshot.version);

        expect(
          workflow.lifecycle,
          same(client_runtime.lifecycles[CounterFeatureModule.lifecycle_id]),
        );

        final CounterSlice? counter = workflow.slice(CounterSlice.key);

        final FindingsSlice? findings = workflow.slice(FindingsSlice.key);

        expect(counter, isNotNull);
        expect(counter!.count, 42);

        expect(findings, isNotNull);
        expect(findings!.finding, 'Obsolete SDK');

        expect(client_codec.encode(restored), payload);
      },
    );

    test('rejects malformed application-state representations', () {
      final invalid_payloads = <Object?>[
        null,
        [],
        'state',
        <String, Object?>{},
        {'workflows': null},
        {'workflows': <String, Object?>{}},
        {
          'workflows': {'current_workflow': null},
          'unexpected': null,
        },
      ];

      for (final payload in invalid_payloads) {
        expect(
          () => client_codec.decode(payload),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('does not interpret an invalid snapshot as verified absence', () {
      final payload = <String, Object?>{
        'workflows': {
          'current_workflow': {'invalid': true},
        },
      };

      expect(
        () => client_codec.decode(payload),
        throwsA(isA<FormatException>()),
      );

      expect(
        client_codec.decode(absent_payload).workflows.current_workflow,
        isNull,
      );
    });

    test('rejects application state containing unsupported feature slices', () {
      final incomplete_runtime = create_serialization_runtime(
        features: [const CounterFeatureModule()],
      );

      final incomplete_codec = RudraStateCodec(runtime: incomplete_runtime);

      final payload = host_codec.encode(state);

      expect(
        () => incomplete_codec.decode(payload),
        throwsA(isA<FormatException>()),
      );
    });

    test('requires complete serialization configuration at construction', () {
      final runtime = create_serialization_runtime(
        features: [const DomainOnlyFeatureModule()],
      );

      expect(() => RudraStateCodec(runtime: runtime), throwsStateError);
    });
  });
}
