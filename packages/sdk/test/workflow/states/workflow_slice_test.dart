import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

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

final class _InspectionSlice extends WorkflowSlice {
  const _InspectionSlice(this.root);

  final String root;
}

final class _PlanningSlice extends WorkflowSlice {
  const _PlanningSlice();
}
