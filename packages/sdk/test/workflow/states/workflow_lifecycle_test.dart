import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('WorkflowLifecycle', () {
    test('preserves lifecycle identity and terminality', () {
      final active = WorkflowLifecycle(
        id: 'rudra.workflow.active',
        is_terminal: false,
      );

      final ended = WorkflowLifecycle(
        id: 'rudra.workflow.ended',
        is_terminal: true,
      );

      expect(active.id, 'rudra.workflow.active');
      expect(active.is_terminal, isFalse);
      expect(ended.is_terminal, isTrue);
    });

    test('supports stable value equality', () {
      final first = WorkflowLifecycle(
        id: 'rudra.workflow.active',
        is_terminal: false,
      );

      final second = WorkflowLifecycle(
        id: 'rudra.workflow.active',
        is_terminal: false,
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('distinguishes conflicting terminality', () {
      final first = WorkflowLifecycle(
        id: 'rudra.workflow.custom',
        is_terminal: false,
      );

      final second = WorkflowLifecycle(
        id: 'rudra.workflow.custom',
        is_terminal: true,
      );

      expect(first, isNot(second));
    });

    test('rejects blank lifecycle identifiers', () {
      for (final id in ['', ' ', '\t', '\n']) {
        expect(
          () => WorkflowLifecycle(id: id, is_terminal: false),
          throwsArgumentError,
        );
      }
    });
  });
}
