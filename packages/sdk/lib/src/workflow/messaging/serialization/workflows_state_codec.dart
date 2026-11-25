import '../../states/workflows_state.dart';

import '../../workflow_runtime.dart';

import 'workflow_snapshot_codec.dart';

/// Serializes the owner-scoped workflow collection.
///
/// Represents the current unfinished workflow or explicitly
/// established absence through the nullable current-workflow selector.
///
/// An unsupported or malformed snapshot is never interpreted
/// as absence.
///
/// Example:
/// ```dart
/// final codec = WorkflowsStateCodec(
///   runtime: WorkflowRuntime.standard(),
/// );
///
/// final restored = codec.decode(codec.encode(workflows));
/// ```
final class WorkflowsStateCodec {
  /// Creates a workflow collection codec using [runtime].
  ///
  /// The runtime supplies the registered workflow snapshot contracts.
  ///
  /// Throws [StateError] when the runtime lacks required slice codecs.
  WorkflowsStateCodec({required WorkflowRuntime runtime})
    : _snapshot_codec = WorkflowSnapshotCodec(runtime: runtime);

  /// Owned serializer for established workflow snapshots.
  final WorkflowSnapshotCodec _snapshot_codec;

  /// Converts [workflows] into its structured representation.
  ///
  /// Returns an explicit current-workflow selector containing
  /// a serialized snapshot or null.
  ///
  /// Snapshot serialization failures propagate.
  Map<String, Object?> encode(WorkflowsState workflows) {
    final current = workflows.current_workflow;

    return {
      'current_workflow': current == null
          ? null
          : _snapshot_codec.encode(current),
    };
  }

  /// Reconstructs a workflow collection from [payload].
  ///
  /// Returns the decoded unfinished workflow or explicit absence.
  ///
  /// Throws [FormatException] for malformed representations,
  /// unsupported snapshots or terminal current workflows.
  ///
  /// Feature-owned codec contract violations propagate.
  WorkflowsState decode(Object? payload) {
    if (payload is! Map<String, Object?> ||
        payload.length != 1 ||
        !payload.containsKey('current_workflow')) {
      throw const FormatException('Invalid workflows state payload.');
    }

    final current_payload = payload['current_workflow'];

    final current = current_payload == null
        ? null
        : _snapshot_codec.decode(current_payload);

    try {
      return WorkflowsState(current_workflow: current);
    } on ArgumentError {
      throw const FormatException('Invalid current workflow state.');
    }
  }
}
