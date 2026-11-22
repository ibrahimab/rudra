import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies workflow slice behavior through this file's focused tests.
void main() {
  group('WorkflowSliceKey', () {
    test('preserves stable identity and concrete type', () {
      final key = WorkflowSliceKey<_InspectionSlice>(
        'rudra.workflow.inspection',
      );

      expect(key.id, 'rudra.workflow.inspection');
      expect(key.slice_type, _InspectionSlice);
    });

    test('validates the concrete slice type', () {
      final key = WorkflowSliceKey<_InspectionSlice>(
        'rudra.workflow.inspection',
      );

      const slice = _InspectionSlice('/tmp');

      expect(key.require_type(slice), same(slice));

      expect(() => key.require_type(const _PlanningSlice()), throwsStateError);
    });

    test('keys have stable typed equality', () {
      final first = WorkflowSliceKey<_InspectionSlice>(
        'rudra.workflow.inspection',
      );

      final second = WorkflowSliceKey<_InspectionSlice>(
        'rudra.workflow.inspection',
      );

      final conflicting = WorkflowSliceKey<_PlanningSlice>(
        'rudra.workflow.inspection',
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(conflicting));
    });

    test('rejects blank slice identifiers', () {
      for (final id in ['', ' ', '\t', '\n']) {
        expect(
          () => WorkflowSliceKey<_InspectionSlice>(id),
          throwsArgumentError,
        );
      }
    });
  });
}

/// Test inspection slice used to verify typed state equality.
final class _InspectionSlice extends WorkflowSlice {
  /// Creates a test inspection slice holding [root].
  const _InspectionSlice(this.root);

  /// Fixture root identifier stored in the typed workflow slice.
  final String root;
}

/// Test planning slice used to verify distinct typed state keys.
final class _PlanningSlice extends WorkflowSlice {
  /// Creates an empty planning slice for typed-key comparison.
  const _PlanningSlice();
}
