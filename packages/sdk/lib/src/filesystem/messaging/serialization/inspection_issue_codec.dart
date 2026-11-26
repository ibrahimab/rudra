import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import '../../inspection_issue.dart';

/// Serializes typed filesystem inspection issues.
///
/// Preserves the failure classification, inspection operation,
/// target-native path and diagnostic message.
///
/// Example:
/// ```dart
/// const codec = InspectionIssueCodec();
/// final payload = codec.encode(issue);
/// final restored = codec.decode(payload);
///
/// print(restored.code.name);
/// ```
final class InspectionIssueCodec {
  /// Creates the stateless inspection issue codec.
  const InspectionIssueCodec();

  /// Converts [issue] into its structured representation.
  ///
  /// Returns the typed inspection failure and its associated
  /// target-native path and diagnostic message.
  Map<String, Object?> encode(InspectionIssue issue) {
    return {
      'code': issue.code.name,
      'operation': issue.operation.name,
      'path': issue.path.value,
      'message': issue.message,
    };
  }

  /// Reconstructs an inspection issue from [payload].
  ///
  /// Returns the validated inspection failure representation.
  /// Throws [FormatException] for malformed representations,
  /// unsupported classifications or invalid domain values.
  InspectionIssue decode(Object? payload) {
    if (payload is! Map<String, Object?> || payload.length != 4) {
      throw const FormatException('Invalid inspection issue payload.');
    }

    final code = payload['code'];
    final operation = payload['operation'];
    final path = payload['path'];
    final message = payload['message'];

    if (code is! String ||
        operation is! String ||
        path is! String ||
        message is! String) {
      throw const FormatException('Invalid inspection issue fields.');
    }

    try {
      return InspectionIssue(
        code: TargetInspectionErrorCode.values.byName(code),
        operation: TargetInspectionOperation.values.byName(operation),
        path: TargetPath(path),
        message: message,
      );
    } on ArgumentError {
      throw const FormatException('Invalid inspection issue values.');
    }
  }
}
