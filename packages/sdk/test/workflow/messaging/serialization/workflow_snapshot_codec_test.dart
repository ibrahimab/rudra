import 'dart:convert';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_sdk/src/workflow/messaging/serialization/workflow_snapshot_codec.dart';
import 'package:test/test.dart';

import '../fixtures/serialization_features.dart';

/// Verifies composite workflow snapshot serialization and
/// feature-owned typed reconstruction.
void main() {
  final identity = WorkflowIdentity(
    workflow_id: 'workflow-001',
    os_user_id: 'user-001',
    target_id: 'local-macos',
    root: TargetPath('/workspace'),
  );

  final counter_binding = WorkflowSliceBinding<CounterSlice>(
    key: CounterSlice.key,
    value: const CounterSlice(42),
  );

  final findings_binding = WorkflowSliceBinding<FindingsSlice>(
    key: FindingsSlice.key,
    value: const FindingsSlice('Obsolete SDK'),
  );

  final host_runtime = create_serialization_runtime(
    features: [const CounterFeatureModule(), const FindingsFeatureModule()],
  );

  final client_runtime = create_serialization_runtime(
    features: [const FindingsFeatureModule(), const CounterFeatureModule()],
  );

  final host_codec = WorkflowSnapshotCodec(runtime: host_runtime);

  final client_codec = WorkflowSnapshotCodec(runtime: client_runtime);

  final active = host_runtime.lifecycles['rudra.workflow.active']!;
  final ended = host_runtime.lifecycles['rudra.workflow.ended']!;

  final valid_snapshot = WorkflowSnapshot(
    identity: identity,
    lifecycle: active,
    version: 12,
    slices: [findings_binding, counter_binding],
  );

  final valid_payload = <String, Object?>{
    'identity': {
      'workflow_id': identity.workflow_id,
      'os_user_id': identity.os_user_id,
      'target_id': identity.target_id,
      'root': identity.root.value,
    },
    'version': 12,
    'lifecycle': 'rudra.workflow.active',
    'slices': [
      {
        'id': CounterSlice.key.id,
        'schema_version': 1,
        'payload': {'count': 42},
      },
      {
        'id': FindingsSlice.key.id,
        'schema_version': 1,
        'payload': 'Obsolete SDK',
      },
    ],
  };

  final counter_payload = <String, Object?>{
    'id': CounterSlice.key.id,
    'schema_version': 1,
    'payload': {'count': 42},
  };

  group('serialization configuration', () {
    test('supports the standard workflow runtime', () {
      final runtime = WorkflowRuntime.standard();

      expect(() => WorkflowSnapshotCodec(runtime: runtime), returnsNormally);
    });

    test('requires codec coverage for every registered slice', () {
      final runtime = create_serialization_runtime(
        features: [const DomainOnlyFeatureModule()],
      );

      expect(runtime.slice_keys, hasLength(1));
      expect(runtime.slice_codecs, isEmpty);

      expect(() => WorkflowSnapshotCodec(runtime: runtime), throwsStateError);
    });
  });

  group('typed snapshot reconstruction', () {
    test('exchanges independent feature slices across runtimes', () {
      expect(identical(host_runtime, client_runtime), isFalse);

      final payload = host_codec.encode(valid_snapshot);

      expect(payload, valid_payload);

      final restored = client_codec.decode(jsonDecode(jsonEncode(payload)));

      expect(restored.identity.workflow_id, identity.workflow_id);
      expect(restored.identity.os_user_id, identity.os_user_id);
      expect(restored.identity.target_id, identity.target_id);
      expect(restored.identity.root.value, identity.root.value);
      expect(restored.version, valid_snapshot.version);

      expect(restored.lifecycle, same(client_runtime.lifecycles[active.id]));

      expect(restored.slice(CounterSlice.key), isA<CounterSlice>());

      expect(restored.slice(CounterSlice.key)!.count, 42);

      expect(restored.slice(FindingsSlice.key), isA<FindingsSlice>());

      expect(restored.slice(FindingsSlice.key)!.finding, 'Obsolete SDK');

      expect(
        restored.slice_bindings.whereType<WorkflowSliceBinding<CounterSlice>>(),
        hasLength(1),
      );

      expect(
        restored.slice_bindings
            .whereType<WorkflowSliceBinding<FindingsSlice>>(),
        hasLength(1),
      );

      expect(client_codec.encode(restored), payload);
    });

    test('encodes slices independently of binding order', () {
      final reordered = WorkflowSnapshot(
        identity: identity,
        lifecycle: active,
        version: 12,
        slices: [counter_binding, findings_binding],
      );

      expect(host_codec.encode(valid_snapshot), host_codec.encode(reordered));

      expect(host_codec.encode(valid_snapshot), client_codec.encode(reordered));
    });

    test('reconstructs feature-owned lifecycle definitions', () {
      final lifecycle =
          host_runtime.lifecycles[CounterFeatureModule.lifecycle_id]!;

      final snapshot = WorkflowSnapshot(
        identity: identity,
        lifecycle: lifecycle,
        version: 3,
      );

      final payload = host_codec.encode(snapshot);

      expect(payload['lifecycle'], CounterFeatureModule.lifecycle_id);

      final restored = client_codec.decode(payload);

      expect(
        restored.lifecycle,
        same(client_runtime.lifecycles[CounterFeatureModule.lifecycle_id]),
      );

      expect(restored.is_terminal, isFalse);
    });

    test('preserves terminal historical snapshots', () {
      final snapshot = WorkflowSnapshot(
        identity: identity,
        lifecycle: ended,
        version: 13,
      );

      final restored = client_codec.decode(host_codec.encode(snapshot));

      expect(restored.is_terminal, isTrue);

      expect(restored.lifecycle, same(client_runtime.lifecycles[ended.id]));
    });

    test('permits registered slices to be absent from snapshots', () {
      final snapshot = WorkflowSnapshot(
        identity: identity,
        lifecycle: active,
        version: 1,
      );

      final payload = host_codec.encode(snapshot);

      expect(payload['slices'], isEmpty);

      final restored = client_codec.decode(payload);

      expect(restored.slice_bindings, isEmpty);
      expect(restored.slice(CounterSlice.key), isNull);
      expect(restored.slice(FindingsSlice.key), isNull);
    });

    test('distinguishes null feature payloads from absent slices', () {
      final snapshot = WorkflowSnapshot(
        identity: identity,
        lifecycle: active,
        version: 2,
        slices: [
          WorkflowSliceBinding<FindingsSlice>(
            key: FindingsSlice.key,
            value: const FindingsSlice(null),
          ),
        ],
      );

      final payload = host_codec.encode(snapshot);

      expect(payload['slices'], [
        {'id': FindingsSlice.key.id, 'schema_version': 1, 'payload': null},
      ]);

      final restored = client_codec.decode(jsonDecode(jsonEncode(payload)));

      expect(restored.slice(FindingsSlice.key), isNotNull);
      expect(restored.slice(FindingsSlice.key)!.finding, isNull);
      expect(restored.slice(CounterSlice.key), isNull);
    });
  });

  group('encoding integrity', () {
    test('rejects unregistered lifecycle definitions', () {
      final snapshot = WorkflowSnapshot(
        identity: identity,
        lifecycle: WorkflowLifecycle(id: 'test.unknown', is_terminal: false),
        version: 1,
      );

      expect(() => host_codec.encode(snapshot), throwsStateError);
    });

    test('rejects conflicting registered lifecycle terminality', () {
      final snapshot = WorkflowSnapshot(
        identity: identity,
        lifecycle: WorkflowLifecycle(id: active.id, is_terminal: true),
        version: 1,
      );

      expect(() => host_codec.encode(snapshot), throwsStateError);
    });

    test('rejects unregistered slice identities', () {
      final snapshot = WorkflowSnapshot(
        identity: identity,
        lifecycle: active,
        version: 1,
        slices: [
          WorkflowSliceBinding<CounterSlice>(
            key: WorkflowSliceKey<CounterSlice>('test.unknown'),
            value: const CounterSlice(42),
          ),
        ],
      );

      expect(() => host_codec.encode(snapshot), throwsStateError);
    });

    test('rejects incompatible slice types for registered identities', () {
      final snapshot = WorkflowSnapshot(
        identity: identity,
        lifecycle: active,
        version: 1,
        slices: [
          WorkflowSliceBinding<FindingsSlice>(
            key: WorkflowSliceKey<FindingsSlice>(CounterSlice.key.id),
            value: const FindingsSlice('Incompatible'),
          ),
        ],
      );

      expect(() => host_codec.encode(snapshot), throwsStateError);
    });
  });

  group('decoding integrity', () {
    test('rejects malformed snapshot representations', () {
      final invalid_payloads = <Object?>[
        null,
        [],
        'workflow-001',
        <String, Object?>{},
        {...valid_payload, 'unexpected': true},
        {...valid_payload, 'identity': null},
        {...valid_payload, 'slices': null},
        {...valid_payload, 'slices': {}},
      ];

      for (final payload in invalid_payloads) {
        expect(
          () => client_codec.decode(payload),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('rejects missing mandatory snapshot fields', () {
      for (final field in valid_payload.keys) {
        final payload = Map<String, Object?>.of(valid_payload)..remove(field);

        expect(
          () => client_codec.decode(payload),
          throwsA(isA<FormatException>()),
          reason: 'Missing snapshot field: $field',
        );
      }
    });

    test('rejects invalid committed workflow versions', () {
      final invalid_versions = <Object?>[null, 0, -1, 1.5, '12', true];

      for (final version in invalid_versions) {
        expect(
          () => client_codec.decode({...valid_payload, 'version': version}),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('rejects unknown or malformed lifecycle representations', () {
      final invalid_lifecycles = <Object?>[
        null,
        '',
        42,
        'test.unknown',
        {'id': active.id, 'is_terminal': false},
      ];

      for (final lifecycle in invalid_lifecycles) {
        expect(
          () => client_codec.decode({...valid_payload, 'lifecycle': lifecycle}),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('rejects malformed slice representations', () {
      final invalid_slices = <Object?>[
        null,
        [],
        'test.counter',
        <String, Object?>{},
        {'id': CounterSlice.key.id, 'schema_version': 1},
        {...counter_payload, 'id': 42},
        {...counter_payload, 'unexpected': null},
        {'id': FindingsSlice.key.id, 'schema_version': 1, 'unexpected': null},
      ];

      for (final slice in invalid_slices) {
        expect(
          () => client_codec.decode({
            ...valid_payload,
            'slices': [slice],
          }),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('rejects unsupported slice schema versions', () {
      final invalid_versions = <Object?>[null, 0, -1, 2, 1.5, '1'];

      for (final version in invalid_versions) {
        expect(
          () => client_codec.decode({
            ...valid_payload,
            'slices': [
              {...counter_payload, 'schema_version': version},
            ],
          }),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('rejects duplicate slice identities', () {
      expect(
        () => client_codec.decode({
          ...valid_payload,
          'slices': [counter_payload, counter_payload],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects unknown slice identifiers', () {
      expect(
        () => client_codec.decode({
          ...valid_payload,
          'slices': [
            {...counter_payload, 'id': 'test.unknown'},
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('propagates feature payload decoding failures', () {
      expect(
        () => client_codec.decode({
          ...valid_payload,
          'slices': [
            {
              ...counter_payload,
              'payload': {'count': '42'},
            },
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects snapshots when either feature is unsupported', () {
      final incomplete_configurations = <List<WorkflowModule>>[
        [const CounterFeatureModule()],
        [const FindingsFeatureModule()],
      ];

      for (final features in incomplete_configurations) {
        final runtime = create_serialization_runtime(features: features);

        final codec = WorkflowSnapshotCodec(runtime: runtime);

        expect(
          () => codec.decode(valid_payload),
          throwsA(isA<FormatException>()),
        );
      }
    });
  });
}
