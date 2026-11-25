import 'package:rudra_communication/rudra_communication.dart';

import '../../../messaging/application_request_context.dart';
import '../../../messaging/application_request_handler_module.dart';

import '../../../workflow/workflow_runtime.dart';

import 'codecs/state_subscription_codecs.dart';
import 'state_subscription_handlers.dart';
import 'state_subscription_messages.dart';

/// Contributes application-state subscription messaging capabilities.
///
/// Host composition registers establishment and cancellation handlers.
/// Client composition consumes the same codecs and supplies its
/// delivery receiver independently.
final class StateSubscriptionMessagingModule
    implements ApplicationRequestHandlerModule {
  /// Creates a subscription messaging contribution using [runtime].
  ///
  /// When omitted, the standard workflow runtime is selected.
  ///
  /// Construction does not begin observation or acquire resources.
  StateSubscriptionMessagingModule({WorkflowRuntime? runtime})
    : _runtime = runtime ?? WorkflowRuntime.standard();

  /// Immutable runtime used for composite state serialization.
  final WorkflowRuntime _runtime;

  /// Stable identity of the subscription messaging contribution.
  @override
  String get module_id => 'rudra.state.subscription.messaging';

  /// Contributes typed subscription codecs to [registry].
  ///
  /// Throws [StateError] for missing state serialization capabilities.
  /// Registry validation and registration failures propagate.
  @override
  void register_codecs(MessageCodecRegistry registry) {
    // Validate domain-state serialization before adding registrations.
    final delivery_codec = StateDeliveryRequestCodec(runtime: _runtime);

    registry
      ..register_request<StateSubscribeResponse, StateSubscribeRequest>(
        const StateSubscribeRequestCodec(),
      )
      ..register_response<StateSubscribeResponse>(
        const StateSubscribeResponseCodec(),
      )
      ..register_request<StateDeliveryResponse, StateDeliveryRequest>(
        delivery_codec,
      )
      ..register_response<StateDeliveryResponse>(
        const StateDeliveryResponseCodec(),
      )
      ..register_request<StateUnsubscribeResponse, StateUnsubscribeRequest>(
        const StateUnsubscribeRequestCodec(),
      )
      ..register_response<StateUnsubscribeResponse>(
        const StateUnsubscribeResponseCodec(),
      );
  }

  /// Registers host-side subscription handlers in [registry].
  ///
  /// [context] supplies the authoritative publication and trusted
  /// application ownership boundary.
  ///
  /// Each request verifies peer ownership before subscription access.
  /// Registration does not establish subscriptions.
  @override
  void register_handlers(
    RequestHandlerRegistry registry,
    ApplicationRequestContext context,
  ) {
    final handlers = StateSubscriptionHandlers(
      publication: context.publication,
    );

    registry
      ..register<StateSubscribeResponse, StateSubscribeRequest>((
        request,
        session,
      ) {
        context.require_authorized_peer(session);

        return handlers.subscribe(request, session);
      })
      ..register<StateUnsubscribeResponse, StateUnsubscribeRequest>((
        request,
        session,
      ) {
        context.require_authorized_peer(session);

        return handlers.unsubscribe(request, session);
      });
  }
}
