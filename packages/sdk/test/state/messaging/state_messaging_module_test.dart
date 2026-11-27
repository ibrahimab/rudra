import 'dart:convert';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

import '../../workflow/messaging/fixtures/serialization_features.dart';

/// Verifies application state messaging contribution,
/// runtime selection and extensible public message composition.
void main() {
  const request = StateReadRequest();

  final absent_response = StateReadResponse(
    state: RudraState(workflows: WorkflowsState(current_workflow: null)),
  );

  final host_runtime = create_serialization_runtime(
    features: [const CounterFeatureModule(), const FindingsFeatureModule()],
  );

  final client_runtime = create_serialization_runtime(
    features: [const FindingsFeatureModule(), const CounterFeatureModule()],
  );

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

  final established_response = StateReadResponse(
    state: RudraState(workflows: WorkflowsState(current_workflow: snapshot)),
  );

  group('state messaging contribution', () {
    test('contributes codecs without finalizing configuration', () {
      final module = StateMessagingModule();
      final registry = MessageCodecRegistry();

      expect(module.module_id, 'rudra.state.messaging');

      module.register_codecs(registry);

      expect(registry.is_frozen, isFalse);

      registry.freeze();

      expect(registry.is_frozen, isTrue);

      expect(registry.response_type_for(request), StateReadResponse);
    });

    test('coexists with standard workflow messaging capabilities', () {
      final modules = standard_messaging_modules();

      final state_modules = modules.whereType<StateMessagingModule>();

      expect(state_modules, hasLength(1));

      expect(state_modules.single.module_id, 'rudra.state.messaging');

      final registry = create_application_message_codecs();

      expect(registry.is_frozen, isTrue);

      expect(registry.response_type_for(request), StateReadResponse);

      expect(
        registry.response_type_for(
          WorkflowStartRequest(
            root: TargetPath('/workspace'),
            idempotency_key: 'operation-001',
          ),
        ),
        WorkflowStartResponse,
      );

      expect(
        registry.response_type_for(
          WorkflowStopRequest(
            workflow_id: 'workflow-001',
            idempotency_key: 'operation-002',
          ),
        ),
        WorkflowStopResponse,
      );

      expect(
        registry.response_type_for(
          WorkflowSubmissionRequest(
            receipt: EventSubmissionReceipt(
              event_id: 'event-001',
              correlation_id: 'correlation-001',
            ),
          ),
        ),
        WorkflowSubmissionResponse,
      );
    });

    test('supports explicit state-only messaging composition', () {
      final registry = create_application_message_codecs(
        modules: [StateMessagingModule()],
      );

      expect(registry.is_frozen, isTrue);

      expect(registry.response_type_for(request), StateReadResponse);

      expect(
        () => registry.encode(
          WorkflowStartRequest(
            root: TargetPath('/workspace'),
            idempotency_key: 'operation-001',
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('application state message exchange', () {
    test('exchanges standard state messages across independent registries', () {
      final client_codecs = create_application_message_codecs();
      final host_codecs = create_application_message_codecs();

      expect(identical(client_codecs, host_codecs), isFalse);

      final encoded_request = client_codecs.encode(request);

      expect(encoded_request.type_id, 'rudra.state.read.request.v1');

      final received_request = host_codecs.decode(
        encoded_request.type_id,
        jsonDecode(jsonEncode(encoded_request.payload)),
      );

      expect(received_request, isA<StateReadRequest>());

      final encoded_response = host_codecs.encode(absent_response);

      expect(encoded_response.type_id, 'rudra.state.read.response.v1');

      final received_response = client_codecs.decode(
        encoded_response.type_id,
        jsonDecode(jsonEncode(encoded_response.payload)),
      ) as StateReadResponse;

      expect(received_response.state, isA<RudraState>());

      expect(received_response.state.workflows.current_workflow, isNull);
    });

    test('preserves independent feature state through public messaging', () {
      final host_codecs = create_application_message_codecs(
        modules: standard_messaging_modules(workflow_runtime: host_runtime),
      );

      final client_codecs = create_application_message_codecs(
        modules: standard_messaging_modules(workflow_runtime: client_runtime),
      );

      final encoded = host_codecs.encode(established_response);

      expect(encoded.type_id, 'rudra.state.read.response.v1');

      final received = client_codecs.decode(
        encoded.type_id,
        jsonDecode(jsonEncode(encoded.payload)),
      ) as StateReadResponse;

      final current = received.state.workflows.current_workflow!;

      expect(current.identity.workflow_id, identity.workflow_id);
      expect(current.identity.os_user_id, identity.os_user_id);
      expect(current.identity.target_id, identity.target_id);
      expect(current.identity.root.value, identity.root.value);

      expect(current.version, snapshot.version);

      expect(
        current.lifecycle,
        same(client_runtime.lifecycles[CounterFeatureModule.lifecycle_id]),
      );

      final CounterSlice? counter = current.slice(CounterSlice.key);

      final FindingsSlice? findings = current.slice(FindingsSlice.key);

      expect(counter, isNotNull);
      expect(counter!.count, 42);

      expect(findings, isNotNull);
      expect(findings!.finding, 'Obsolete SDK');

      expect(
        current.slice_bindings.whereType<WorkflowSliceBinding<CounterSlice>>(),
        hasLength(1),
      );

      expect(
        current.slice_bindings.whereType<WorkflowSliceBinding<FindingsSlice>>(),
        hasLength(1),
      );

      final reencoded = client_codecs.encode(received);

      expect(reencoded.type_id, encoded.type_id);
      expect(reencoded.payload, encoded.payload);
    });

    test('rejects messages containing unsupported feature state', () {
      final host_codecs = create_application_message_codecs(
        modules: standard_messaging_modules(workflow_runtime: host_runtime),
      );

      final incomplete_configurations = <List<WorkflowModule>>[
        [const CounterFeatureModule()],
        [const FindingsFeatureModule()],
      ];

      final encoded = host_codecs.encode(established_response);

      for (final features in incomplete_configurations) {
        final runtime = create_serialization_runtime(features: features);

        final client_codecs = create_application_message_codecs(
          modules: standard_messaging_modules(workflow_runtime: runtime),
        );

        expect(
          () => client_codecs.decode(
            encoded.type_id,
            jsonDecode(jsonEncode(encoded.payload)),
          ),
          throwsA(isA<FormatException>()),
        );
      }
    });
  });

  group('configuration integrity', () {
    test(
      'rejects incomplete serialization configuration before contribution',
      () {
        final runtime = create_serialization_runtime(
          features: [const DomainOnlyFeatureModule()],
        );

        final module = StateMessagingModule(runtime: runtime);

        final registry = MessageCodecRegistry();

        expect(() => module.register_codecs(registry), throwsStateError);

        expect(registry.is_frozen, isFalse);

        // Neither State Read codec may have been contributed
        // when state serialization configuration is invalid.
        registry.freeze();

        expect(() => registry.encode(request), throwsArgumentError);

        expect(() => registry.encode(absent_response), throwsArgumentError);

        expect(
          () => create_application_message_codecs(
            modules: standard_messaging_modules(workflow_runtime: runtime),
          ),
          throwsStateError,
        );
      },
    );

    test('excludes state messaging when standard modules are replaced', () {
      final registry = create_application_message_codecs(modules: []);

      expect(registry.is_frozen, isTrue);

      expect(() => registry.encode(request), throwsArgumentError);

      expect(() => registry.encode(absent_response), throwsArgumentError);
    });
  });
}
