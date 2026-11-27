import 'package:rudra_sdk/rudra_sdk.dart';

/// Rejects unexpected filesystem inspection in host integration tests.
///
/// Used when the configured host is exercising application capabilities
/// unrelated to filesystem observation.
///
/// Example:
/// ```dart
/// final inspector = UnusedTargetInspector();
/// ```
final class UnusedTargetInspector implements TargetInspector {
  /// Creates an inspection fixture that rejects every operation.
  const UnusedTargetInspector();

  /// Rejects an unexpected inspection [invocation].
  ///
  /// Throws [UnsupportedError] for every target operation.
  @override
  Never noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'Unexpected filesystem inspection: ${invocation.memberName}',
    );
  }
}
