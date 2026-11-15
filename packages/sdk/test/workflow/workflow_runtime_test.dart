import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies immutable configuration of workflow capabilities.
///
/// A WorkflowRuntime is the application-level snapshot of
/// module registrations. Consumers share its flow, codec,
/// and command behaviors without rebuilding them independently.
void main() {
  test('builds consistent standard workflow capabilities', () {
    final runtime = WorkflowRuntime.standard();

    // The state machine recognizes both events involved
    // in successful workflow establishment.
    expect(runtime.flow.supports_event_type(WorkflowStartEvent), isTrue);

    expect(runtime.flow.supports_event_type(WorkflowStartedEvent), isTrue);

    // The same configuration supplies the command handler.
    expect(runtime.command_behaviors[WorkflowStartEvent], isNotNull);

    // The codec understands the command registered by
    // the lifecycle module.
    final request = WorkflowStartEvent(
      target_id: 'local-macos',
      root: TargetPath('/workspace'),
    );

    final payload = runtime.codec.encode(request);

    final decoded = runtime.codec.decode(
      event_type: request.event_type,
      payload_json: payload,
    );

    expect(decoded, isA<WorkflowStartEvent>());

    // Callers cannot mutate the runtime handler mapping.
    expect(() => runtime.command_behaviors.clear(), throwsUnsupportedError);
  });
}
