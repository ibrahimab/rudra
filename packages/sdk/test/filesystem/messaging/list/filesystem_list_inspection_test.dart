import 'dart:async';

import 'package:rudra_sdk/rudra_sdk.dart';

import 'package:rudra_sdk/src/filesystem/messaging/list/filesystem_list_inspection.dart';
import 'package:rudra_sdk/src/filesystem/messaging/list/filesystem_list_messages.dart';
import 'package:rudra_sdk/src/filesystem/messaging/list/codecs/filesystem_list_codecs.dart';

import 'package:test/test.dart';

/// Verifies bounded advancement and inspection resource disposal.
void main() {
  final request = FilesystemListOpenRequest(
    inspection_id: 'inspection-001',
    target_id: 'local-macos',
    directory: TargetPath('/workspace'),
  );

  const codec = FilesystemListBatchResponseCodec();

  group('FilesystemListInspection', () {
    test('defers observation acquisition until advancement', () async {
      var started = false;
      var released = false;

      Stream<FilesystemObservation> observe() async* {
        started = true;

        try {
          yield FilesystemObservation.success(_entry(1));
        } finally {
          released = true;
        }
      }

      final inspection = FilesystemListInspection(
        request: request,
        observations: observe(),
      );

      addTearDown(inspection.close);

      expect(started, isFalse);

      final response = await inspection.next(sequence: 1);

      expect(started, isTrue);
      expect(released, isTrue);
      expect(response.status, FilesystemListBatchStatus.complete);
      expect(response.entries.single.path.value, '/workspace/1');
      expect(inspection.is_retired, isTrue);
    });

    test('preserves observations across count-bounded batches', () async {
      const capacity = FilesystemListBatchResponse.maximum_observations;

      final expected = List.generate(capacity * 2 + 1, _entry);

      final inspection = FilesystemListInspection(
        request: request,
        observations: Stream.fromIterable(
          expected.map(FilesystemObservation.success),
        ),
        work_budget: const Duration(minutes: 1),
      );

      addTearDown(inspection.close);

      final first = await inspection.next(sequence: 1);
      final second = await inspection.next(sequence: 2);
      final third = await inspection.next(sequence: 3);

      expect(first.observation_count, capacity);
      expect(second.observation_count, capacity);
      expect(third.observation_count, 1);

      expect(first.status, FilesystemListBatchStatus.more);
      expect(second.status, FilesystemListBatchStatus.more);
      expect(third.status, FilesystemListBatchStatus.complete);

      expect([...first.entries, ...second.entries, ...third.entries], expected);
    });

    test('retains lookahead across byte-bounded batches', () async {
      const capacity = FilesystemListBatchResponseCodec.maximum_payload_bytes;

      final message = List.filled(capacity ~/ 2, 'x').join();

      final first_issue = _issue(message);
      final second_issue = _issue(message);

      final inspection = FilesystemListInspection(
        request: request,
        observations: Stream.fromIterable([
          FilesystemObservation.failure(first_issue),
          FilesystemObservation.failure(second_issue),
        ]),
        work_budget: const Duration(minutes: 1),
      );

      addTearDown(inspection.close);

      final first = await inspection.next(sequence: 1);
      final second = await inspection.next(sequence: 2);

      expect(first.issues, [first_issue]);
      expect(second.issues, [second_issue]);

      expect(first.status, FilesystemListBatchStatus.more);
      expect(second.status, FilesystemListBatchStatus.incomplete);

      for (final response in [first, second]) {
        expect(codec.payload_size(response), lessThanOrEqualTo(capacity));
      }
    });

    test('retains incomplete status across subsequent batches', () async {
      const capacity = FilesystemListBatchResponse.maximum_observations;

      final issue = _issue('Permission denied.');

      final observations = [
        FilesystemObservation.failure(issue),
        ...List.generate(
          capacity,
          (index) => FilesystemObservation.success(_entry(index)),
        ),
      ];

      final inspection = FilesystemListInspection(
        request: request,
        observations: Stream.fromIterable(observations),
        work_budget: const Duration(minutes: 1),
      );

      addTearDown(inspection.close);

      final first = await inspection.next(sequence: 1);
      final second = await inspection.next(sequence: 2);

      expect(first.issues, [issue]);
      expect(first.status, FilesystemListBatchStatus.more);

      expect(second.issues, isEmpty);
      expect(second.status, FilesystemListBatchStatus.incomplete);
    });

    test('returns a terminal batch for an empty directory', () async {
      final inspection = FilesystemListInspection(
        request: request,
        observations: const Stream<FilesystemObservation>.empty(),
      );

      addTearDown(inspection.close);

      final response = await inspection.next(sequence: 1);

      expect(response.observation_count, 0);
      expect(response.status, FilesystemListBatchStatus.complete);
      expect(inspection.is_retired, isTrue);
    });

    test('rejects an individually oversized observation', () async {
      const capacity = FilesystemListBatchResponseCodec.maximum_payload_bytes;

      final inspection = FilesystemListInspection(
        request: request,
        observations: Stream.value(
          FilesystemObservation.failure(
            _issue(List.filled(capacity + 1, 'x').join()),
          ),
        ),
      );

      addTearDown(inspection.close);

      await expectLater(inspection.next(sequence: 1), throwsFormatException);

      expect(inspection.is_retired, isTrue);
    });

    test('rejects invalid sequences without retiring inspection', () async {
      final inspection = FilesystemListInspection(
        request: request,
        observations: Stream.value(FilesystemObservation.success(_entry(1))),
      );

      addTearDown(inspection.close);

      await expectLater(inspection.next(sequence: 2), throwsStateError);

      expect(inspection.is_retired, isFalse);

      final response = await inspection.next(sequence: 1);

      expect(response.status, FilesystemListBatchStatus.complete);
    });

    test('rejects concurrent advancement', () async {
      final controller = StreamController<FilesystemObservation>();

      final inspection = FilesystemListInspection(
        request: request,
        observations: controller.stream,
      );

      addTearDown(inspection.close);

      final pending = inspection.next(sequence: 1);

      await expectLater(inspection.next(sequence: 1), throwsStateError);

      controller.add(FilesystemObservation.success(_entry(1)));

      await controller.close();

      final response = await pending;

      expect(response.entries, hasLength(1));
    });

    test('releases retained source during explicit cancellation', () async {
      var released = false;

      Stream<FilesystemObservation> observe() async* {
        try {
          for (
            var index = 0;
            index <= FilesystemListBatchResponse.maximum_observations;
            index++
          ) {
            yield FilesystemObservation.success(_entry(index));
          }
        } finally {
          released = true;
        }
      }

      final inspection = FilesystemListInspection(
        request: request,
        observations: observe(),
        work_budget: const Duration(minutes: 1),
      );

      addTearDown(inspection.close);

      final first = await inspection.next(sequence: 1);

      expect(first.status, FilesystemListBatchStatus.more);
      expect(released, isFalse);

      await inspection.close();

      expect(released, isTrue);
      expect(inspection.is_retired, isTrue);

      await expectLater(inspection.next(sequence: 2), throwsStateError);
    });

    test('cancellation invalidates an outstanding advancement', () async {
      final subscribed = Completer<void>();
      final cancelled = Completer<void>();

      final controller = StreamController<FilesystemObservation>(
        onListen: subscribed.complete,
        onCancel: cancelled.complete,
      );

      final inspection = FilesystemListInspection(
        request: request,
        observations: controller.stream,
      );

      addTearDown(inspection.close);

      final pending = inspection.next(sequence: 1);

      final failure = expectLater(pending, throwsStateError);

      await subscribed.future;

      await inspection.close();

      await failure;
      await cancelled.future;

      expect(inspection.is_retired, isTrue);

      await controller.close();
    });

    test('unexpected source failures retire the inspection', () async {
      final inspection = FilesystemListInspection(
        request: request,
        observations: Stream.error(StateError('Unexpected source failure.')),
      );

      addTearDown(inspection.close);

      await expectLater(inspection.next(sequence: 1), throwsStateError);

      expect(inspection.is_retired, isTrue);
    });

    test('closing before advancement acquires no resources', () async {
      var subscribed = false;

      Stream<FilesystemObservation> observe() async* {
        subscribed = true;

        yield FilesystemObservation.success(_entry(1));
      }

      final inspection = FilesystemListInspection(
        request: request,
        observations: observe(),
      );

      final first = inspection.close();
      final second = inspection.close();

      expect(first, same(second));

      await first;

      expect(subscribed, isFalse);
    });
  });
}

/// Creates a deterministic entry identified by [index].
FilesystemEntry _entry(int index) {
  return FilesystemEntry(
    path: TargetPath('/workspace/$index'),
    kind: FilesystemEntryKind.regularFile,
    metadata: FilesystemMetadata(),
  );
}

/// Creates a typed inspection issue containing [message].
InspectionIssue _issue(String message) {
  return InspectionIssue(
    code: TargetInspectionErrorCode.permissionDenied,
    operation: TargetInspectionOperation.inspect,
    path: TargetPath('/workspace/restricted'),
    message: message,
  );
}
