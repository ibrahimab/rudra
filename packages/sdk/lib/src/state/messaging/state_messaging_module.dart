import 'package:rudra_communication/rudra_communication.dart';

import '../../messaging/application_messaging_module.dart';

import '../../workflow/workflow_runtime.dart';

import 'read/state_read_request.dart';
import 'read/state_read_response.dart';
import 'read/codecs/state_read_request_codec.dart';
import 'read/codecs/state_read_response_codec.dart';

/// Contributes composite application state messaging capabilities.
///
/// The supplied workflow runtime determines the lifecycle and
/// feature-owned slice contracts available for state serialization.
///
/// Standard construction selects the standard Rudra workflow runtime.
/// Explicit composition may supply an independently configured runtime.
///
/// Example:
/// ```dart
/// final codecs = create_application_message_codecs(
///   modules: [StateMessagingModule(runtime: runtime)],
/// );
/// ```
final class StateMessagingModule implements ApplicationMessagingModule {
  /// Creates a composite application state messaging module.
  ///
  /// [runtime] supplies the immutable workflow configuration.
  /// When omitted, the standard workflow runtime is constructed.
  ///
  /// Construction does not read state or acquire communication
  /// or persistence resources.
  StateMessagingModule({WorkflowRuntime? runtime})
    : _runtime = runtime ?? WorkflowRuntime.standard();

  /// Workflow configuration used by contributed state codecs.
  final WorkflowRuntime _runtime;

  /// Stable identifier of the application state messaging contribution.
  @override
  String get module_id => 'rudra.state.messaging';

  /// Contributes application state message codecs to [registry].
  ///
  /// The application composition boundary validates and freezes
  /// the completed message configuration.
  ///
  /// Throws [StateError] when the configured workflow runtime
  /// lacks required slice serialization capabilities.
  ///
  /// Registration failures propagate from the supplied registry.
  @override
  void register_codecs(MessageCodecRegistry registry) {
    // Validate the state serialization configuration before
    // publishing either message codec to the supplied registry.
    final response_codec = StateReadResponseCodec(runtime: _runtime);

    registry
      ..register_request<StateReadResponse, StateReadRequest>(
        const StateReadRequestCodec(),
      )
      ..register_response<StateReadResponse>(response_codec);
  }
}
