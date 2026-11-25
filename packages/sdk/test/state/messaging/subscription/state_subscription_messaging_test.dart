import 'dart:convert';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

import '../../../workflow/messaging/fixtures/serialization_features.dart';

/// Verifies subscription messaging and feature-owned state serialization.
void main() {
  const subscription_id = 'subscription-1';
  const generation = 'generation-1';

  final state = RudraState(workflows: WorkflowsState(current_workflow: null));

  final publication = StatePublicationSnapshot(
    generation: generation,
    revision: 1,
    state: state,
  );

  test('contributes codecs without freezing the registry', () {
    final module = StateSubscriptionMessagingModule();
    final registry = MessageCodecRegistry();

    expect(module.module_id, 'rudra.state.subscription.messaging');

    module.register_codecs(registry);

    expect(registry.is_frozen, isFalse);

    registry.freeze();

    expect(
      registry.response_type_for(
        StateSubscribeRequest(subscription_id: subscription_id),
      ),
      StateSubscribeResponse,
    );

    expect(
      registry.response_type_for(
        StateDeliveryRequest(
          subscription_id: subscription_id,
          publication: publication,
        ),
      ),
      StateDeliveryResponse,
    );

    expect(
      registry.response_type_for(
        StateUnsubscribeRequest(subscription_id: subscription_id),
      ),
      StateUnsubscribeResponse,
    );
  });

  test('round-trips all six messages through independent registries', () {
    final host = create_application_message_codecs();
    final client = create_application_message_codecs();

    final messages = <Message>[
      StateSubscribeRequest(subscription_id: subscription_id),
      StateSubscribeResponse(
        subscription_id: subscription_id,
        generation: generation,
      ),
      StateDeliveryRequest(
        subscription_id: subscription_id,
        publication: publication,
      ),
      StateDeliveryResponse(
        subscription_id: subscription_id,
        generation: generation,
        revision: 1,
      ),
      StateUnsubscribeRequest(subscription_id: subscription_id),
      StateUnsubscribeResponse(subscription_id: subscription_id),
    ];

    for (final message in messages) {
      final encoded = host.encode(message);

      final decoded = client.decode(
        encoded.type_id,
        jsonDecode(jsonEncode(encoded.payload)),
      );

      expect(decoded.runtimeType, message.runtimeType);

      final reconstructed = client.encode(decoded);

      expect(reconstructed.type_id, encoded.type_id);
      expect(reconstructed.payload, encoded.payload);
    }
  });

  test('rejects malformed subscription message payloads', () {
    final registry = create_application_message_codecs();

    final cases = <(String, Object?)>[
      ('rudra.state.subscribe.request.v1', {'subscription_id': ''}),
      (
        'rudra.state.subscribe.request.v1',
        {'subscription_id': subscription_id, 'os_user_id': 'other-user'},
      ),
      (
        'rudra.state.subscribe.response.v1',
        {'subscription_id': subscription_id},
      ),
      (
        'rudra.state.subscribe.response.v1',
        {'subscription_id': subscription_id, 'generation': ' '},
      ),
      (
        'rudra.state.delivery.request.v1',
        {
          'subscription_id': subscription_id,
          'generation': generation,
          'revision': 0,
          'state': {'workflows': null},
        },
      ),
      (
        'rudra.state.delivery.response.v1',
        {
          'subscription_id': subscription_id,
          'generation': generation,
          'revision': '1',
        },
      ),
      (
        'rudra.state.delivery.response.v1',
        {
          'subscription_id': subscription_id,
          'generation': generation,
          'revision': -1,
        },
      ),
      ('rudra.state.unsubscribe.request.v1', {'subscription_id': 1}),
      ('rudra.state.unsubscribe.response.v1', {}),
    ];

    for (final (type_id, payload) in cases) {
      expect(
        () => registry.decode(type_id, payload),
        throwsFormatException,
        reason: type_id,
      );
    }
  });

  test('rejects invalid publication acknowledgment construction', () {
    expect(
      () => StateDeliveryResponse(
        subscription_id: subscription_id,
        generation: generation,
        revision: 0,
      ),
      throwsArgumentError,
    );
  });

  test('delivery preserves independently registered workflow slices', () {
    final host_runtime = create_serialization_runtime(
      features: [const CounterFeatureModule(), const FindingsFeatureModule()],
    );

    final client_runtime = create_serialization_runtime(
      features: [const FindingsFeatureModule(), const CounterFeatureModule()],
    );

    final host = create_application_message_codecs(
      modules: standard_messaging_modules(workflow_runtime: host_runtime),
    );

    final client = create_application_message_codecs(
      modules: standard_messaging_modules(workflow_runtime: client_runtime),
    );

    final workflow = WorkflowSnapshot(
      identity: WorkflowIdentity(
        workflow_id: 'workflow-1',
        os_user_id: 'trusted-owner',
        target_id: 'local-macos',
        root: TargetPath('/workspace'),
      ),
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

    final encoded = host.encode(
      StateDeliveryRequest(
        subscription_id: subscription_id,
        publication: StatePublicationSnapshot(
          generation: generation,
          revision: 7,
          state: RudraState(
            workflows: WorkflowsState(current_workflow: workflow),
          ),
        ),
      ),
    );

    final decoded = client.decode(
      encoded.type_id,
      jsonDecode(jsonEncode(encoded.payload)),
    ) as StateDeliveryRequest;

    expect(decoded.subscription_id, subscription_id);
    expect(decoded.publication.generation, generation);
    expect(decoded.publication.revision, 7);

    final restored = decoded.publication.state.workflows.current_workflow!;

    expect(restored.identity.workflow_id, 'workflow-1');
    expect(restored.version, 12);

    expect(
      restored.lifecycle,
      same(client_runtime.lifecycles[CounterFeatureModule.lifecycle_id]),
    );

    expect(restored.slice(CounterSlice.key)?.count, 42);

    expect(restored.slice(FindingsSlice.key)?.finding, 'Obsolete SDK');
  });

  test('rejects subscription codecs with missing slice serialization', () {
    final runtime = create_serialization_runtime(
      features: [const DomainOnlyFeatureModule()],
    );

    expect(
      () => create_application_message_codecs(
        modules: [StateSubscriptionMessagingModule(runtime: runtime)],
      ),
      throwsStateError,
    );
  });
}
