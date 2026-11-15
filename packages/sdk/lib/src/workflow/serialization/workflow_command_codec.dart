import 'dart:convert';

import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import '../events/workflow_event.dart';
import '../events/workflow_start_event.dart';

/// Encodes and decodes versioned workflow commands.
///
/// Event representations are independent of persistence adapters.
///
/// Unknown event types and schema versions are rejected rather
/// than silently interpreted.
final class WorkflowCommandCodec {
  /// Creates a stateless workflow command codec.
  const WorkflowCommandCodec();

  /// Current supported command payload schema version.
  static const int schema_version = 1;

  /// Encodes a typed workflow command into canonical JSON.
  ///
  /// Example:
  /// ```dart
  /// final payload = codec.encode(event);
  /// ```
  String encode(WorkflowCommandEvent event) {
    return switch (event) {
      WorkflowStartEvent() => jsonEncode({
        'schema_version': schema_version,
        'target_id': event.target_id,
        'root': event.root.value,
      }),
      _ => throw UnsupportedError(
        'Unsupported workflow command: ${event.event_type}',
      ),
    };
  }

  /// Reconstructs a typed command from its persisted representation.
  ///
  /// Rejects unsupported event types, versions, and malformed data.
  WorkflowCommandEvent decode({
    required String event_type,
    required String payload_json,
  }) {
    final decoded = jsonDecode(payload_json);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid workflow command payload.');
    }

    if (decoded['schema_version'] != schema_version) {
      throw const FormatException('Unsupported command schema version.');
    }

    if (event_type != WorkflowStartEvent.type_id) {
      throw FormatException('Unsupported workflow command: $event_type');
    }

    final target_id = decoded['target_id'];
    final root = decoded['root'];

    if (target_id is! String || root is! String) {
      throw const FormatException('Invalid workflow start payload.');
    }

    try {
      return WorkflowStartEvent(target_id: target_id, root: TargetPath(root));
    } on ArgumentError catch (error) {
      throw FormatException('Invalid workflow start payload: $error');
    }
  }
}
