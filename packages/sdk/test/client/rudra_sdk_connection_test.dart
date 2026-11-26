import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies public SDK connection composition and configuration boundaries.
void main() {
  test('local inspection does not require host connectivity', () async {
    final sdk = RudraSdk(
      target_id: 'local-macos',
      inspector: _UnusedInspector(),
    );

    expect(sdk.is_connected, isFalse);
    expect(sdk.resources_released, isTrue);
    expect(sdk.filesystem.target_id, 'local-macos');

    await expectLater(sdk.connect(), throwsStateError);
    await expectLater(sdk.reconnect(), throwsStateError);

    await sdk.close();

    expect(sdk.resources_released, isTrue);
  });

  test(
    'host connection configuration remains inactive on construction',
    () async {
      var resolutions = 0;

      final sdk = RudraSdk(
        target_id: 'local-macos',
        inspector: _UnusedInspector(),
        connection_setup: () {
          resolutions++;

          return (
            scope_directory: '/unused-scope',
            os_user_id: 'trusted-owner',
          );
        },
        communication_factory: ({required codecs, required handlers}) {
          throw StateError(
            'Communication must not be constructed during initialization.',
          );
        },
      );

      expect(resolutions, 0);
      expect(sdk.is_connected, isFalse);
      expect(sdk.resources_released, isTrue);

      await sdk.close();

      expect(resolutions, 0);
      expect(sdk.resources_released, isTrue);

      await expectLater(sdk.connect(), throwsStateError);
    },
  );

  test('rejects connection-specific options without host configuration', () {
    expect(
      () => RudraSdk(
        target_id: 'local-macos',
        inspector: _UnusedInspector(),
        workflow_runtime: WorkflowRuntime.standard(),
      ),
      throwsArgumentError,
    );

    expect(
      () => RudraSdk(
        target_id: 'local-macos',
        inspector: _UnusedInspector(),
        communication_factory: ({required codecs, required handlers}) {
          throw StateError('Unexpected communication construction.');
        },
      ),
      throwsArgumentError,
    );
  });
}

/// Provides a target contract that rejects every inspection operation.
///
/// Connection-only tests use this fixture to establish that SDK
/// connectivity never invokes the filesystem inspection adapter.
///
/// Example:
/// ```dart
/// final inspector = _UnusedInspector();
/// final sdk = RudraSdk(
///   target_id: 'test-target',
///   inspector: inspector,
/// );
/// ```
final class _UnusedInspector implements TargetInspector {
  /// Rejects the unexpected inspection operation in [invocation].
  ///
  /// Throws [UnsupportedError] for every target operation.
  @override
  Never noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'Unexpected filesystem inspection: ${invocation.memberName}',
    );
  }
}
