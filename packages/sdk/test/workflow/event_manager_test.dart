import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies the SDK event-submission boundary.
///
/// The fake store models committed acceptance for contract tests.
/// It does not claim to provide actual durable persistence.
void main() {
  group('EventManager', () {
    test('returns the receipt supplied by the store', () async {
      final receipt = EventSubmissionReceipt(
        event_id: 'event-1',
        correlation_id: 'correlation-1',
      );

      final store = _RecordingStore(receipt);
      final manager = EventManager(store: store);

      final event = WorkflowStartEvent(
        target_id: 'local-macos',
        root: TargetPath('/workspace'),
      );

      final result = await manager.trigger(
        event,
        idempotency_key: 'request-1',
      );

      expect(result, same(receipt));
      expect(store.accepted_event, same(event));
      expect(store.accepted_key, 'request-1');
      expect(store.acceptance_count, 1);
    });

    test('propagates submission failures', () async {
      final manager = EventManager(
        store: _FailingStore(),
      );

      await expectLater(
        manager.trigger(
          WorkflowStartEvent(
            target_id: 'local-macos',
            root: TargetPath('/workspace'),
          ),
        ),
        throwsA(
          isA<EventSubmissionException>().having(
            (error) => error.code,
            'code',
            EventSubmissionErrorCode.persistence_failed,
          ),
        ),
      );
    });

    test('rejects blank receipt identifiers', () {
      expect(
        () => EventSubmissionReceipt(
          event_id: '',
          correlation_id: 'correlation-1',
        ),
        throwsArgumentError,
      );

      expect(
        () => EventSubmissionReceipt(
          event_id: 'event-1',
          correlation_id: ' ',
        ),
        throwsArgumentError,
      );
    });
  });
}

/// Records the command and returns a predefined receipt.
final class _RecordingStore implements EventSubmissionStore {
  /// Creates a deterministic store test double.
  _RecordingStore(this.receipt);

  /// Receipt returned by this test double.
  final EventSubmissionReceipt receipt;

  /// Last accepted command.
  WorkflowCommandEvent? accepted_event;

  /// Last submitted idempotency key.
  String? accepted_key;

  /// Number of acceptance requests.
  int acceptance_count = 0;

  /// Records a submission without implementing persistence.
  @override
  Future<EventSubmissionReceipt> accept(
    WorkflowCommandEvent event, {
    String? idempotency_key,
  }) async {
    accepted_event = event;
    accepted_key = idempotency_key;
    acceptance_count++;

    return receipt;
  }
}

/// Simulates a failed durable acceptance.
final class _FailingStore implements EventSubmissionStore {
  /// Rejects the submission with a typed persistence error.
  @override
  Future<EventSubmissionReceipt> accept(
    WorkflowCommandEvent event, {
    String? idempotency_key,
  }) async {
    throw const EventSubmissionException(
      code: EventSubmissionErrorCode.persistence_failed,
      message: 'Injected persistence failure.',
    );
  }
}
