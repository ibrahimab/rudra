import 'dart:async';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import 'package:rudra_sdk/src/filesystem/messaging/list/filesystem_list_handlers.dart';
import 'package:rudra_sdk/src/filesystem/messaging/list/filesystem_list_messages.dart';

import 'package:test/test.dart';

/// Verifies session-owned filesystem inspection lifecycles.
void main() {
  const target_id = 'test-target';
  const inspection_id = 'inspection-001';

  late _ControlledInspector inspector;
  late FilesystemListHandlers handlers;
  late _TestSession first;
  late _TestSession second;

  /// Creates an admission request for the supplied [id].
  FilesystemListOpenRequest open_request({String id = inspection_id}) {
    return FilesystemListOpenRequest(
      inspection_id: id,

      directory: TargetPath('/workspace'),
    );
  }

  /// Creates an advancement request for [id] at [sequence].
  FilesystemListNextRequest next_request({
    String id = inspection_id,
    int sequence = 1,
  }) {
    return FilesystemListNextRequest(inspection_id: id, sequence: sequence);
  }

  /// Creates a cancellation request for [id].
  FilesystemListCancelRequest cancel_request({String id = inspection_id}) {
    return FilesystemListCancelRequest(inspection_id: id);
  }

  setUp(() {
    inspector = _ControlledInspector();

    handlers = FilesystemListHandlers(
      application: FilesystemApplication(
        target_id: target_id,
        inspector: inspector,
      ),
      maximum_per_session: 2,
      maximum_active: 3,
    );

    first = _TestSession();
    second = _TestSession();
  });

  tearDown(() async {
    inspector.release_inspection();

    await first.close();
    await second.close();
    await handlers.close();
  });

  group('Inspection admission', () {
    test('admission defers native enumeration', () {
      final accepted = handlers.open(open_request(), first);

      expect(accepted.inspection_id, inspection_id);
      expect(handlers.active_count, 1);
      expect(handlers.resources_released, isFalse);

      expect(inspector.enumeration_count, 0);
      expect(inspector.inspection_count, 0);
    });

    test('identifies the host target before native inspection', () {
      final accepted = handlers.open(open_request(), first);

      expect(accepted.target_id, target_id);
      expect(inspector.enumeration_count, 0);
      expect(inspector.inspection_count, 0);
    });

    test('rejects duplicate active inspection identifiers', () {
      handlers.open(open_request(), first);

      expect(() => handlers.open(open_request(), first), throwsStateError);

      expect(handlers.active_count, 1);
    });

    test('enforces session and host admission capacity', () async {
      handlers.open(open_request(id: 'first'), first);
      handlers.open(open_request(id: 'second'), first);

      expect(
        () => handlers.open(open_request(id: 'third'), first),
        throwsStateError,
      );

      handlers.open(open_request(id: 'third'), second);

      expect(handlers.active_count, 3);

      expect(
        () => handlers.open(open_request(id: 'fourth'), second),
        throwsStateError,
      );

      await handlers.cancel(cancel_request(id: 'first'), first);

      expect(handlers.active_count, 2);

      handlers.open(open_request(id: 'fourth'), second);

      expect(handlers.active_count, 3);
    });
  });

  group('Session isolation', () {
    test('rejects advancement through another session', () async {
      handlers.open(open_request(), first);

      await expectLater(
        handlers.next(next_request(), second),
        throwsStateError,
      );

      expect(handlers.active_count, 1);
      expect(inspector.enumeration_count, 0);
    });

    test('equal identifiers remain independent between sessions', () async {
      handlers.open(open_request(), first);
      handlers.open(open_request(), second);

      expect(handlers.active_count, 2);

      await handlers.cancel(cancel_request(), first);

      expect(handlers.active_count, 1);

      final response = await handlers.next(next_request(), second);

      expect(response.status, FilesystemListBatchStatus.complete);
      expect(response.entries, hasLength(1));
      expect(handlers.resources_released, isTrue);
    });

    test(
      'foreign cancellation leaves the original inspection intact',
      () async {
        handlers.open(open_request(), first);

        final cancelled = await handlers.cancel(cancel_request(), second);

        expect(cancelled.inspection_id, inspection_id);
        expect(handlers.active_count, 1);

        final response = await handlers.next(next_request(), first);

        expect(response.status, FilesystemListBatchStatus.complete);
        expect(handlers.resources_released, isTrue);
      },
    );

    test('disconnect retires only the affected session', () async {
      handlers.open(open_request(), first);
      handlers.open(open_request(), second);

      await first.close();

      await _wait_until(() => handlers.active_count == 1);

      expect(
        () => handlers.open(open_request(id: 'new'), first),
        throwsStateError,
      );

      final response = await handlers.next(next_request(), second);

      expect(response.status, FilesystemListBatchStatus.complete);
      expect(handlers.resources_released, isTrue);
    });
  });

  group('Inspection advancement', () {
    test('terminal completion releases admission capacity', () async {
      handlers.open(open_request(), first);

      final response = await handlers.next(next_request(), first);

      expect(response.status, FilesystemListBatchStatus.complete);
      expect(response.entries, hasLength(1));
      expect(inspector.enumeration_count, 1);
      expect(inspector.release_count, 1);
      expect(handlers.resources_released, isTrue);

      await expectLater(
        handlers.next(next_request(sequence: 2), first),
        throwsStateError,
      );
    });

    test('invalid sequence does not retire an admitted inspection', () async {
      handlers.open(open_request(), first);

      await expectLater(
        handlers.next(next_request(sequence: 2), first),
        throwsStateError,
      );

      expect(handlers.active_count, 1);
      expect(inspector.enumeration_count, 0);

      final response = await handlers.next(next_request(), first);

      expect(response.status, FilesystemListBatchStatus.complete);
      expect(handlers.resources_released, isTrue);
    });

    test('rejects overlapping advancement without losing ownership', () async {
      inspector.block_inspection();

      handlers.open(open_request(), first);

      final pending = handlers.next(next_request(), first);

      await inspector.inspection_started.future;

      await expectLater(handlers.next(next_request(), first), throwsStateError);

      expect(handlers.active_count, 1);

      inspector.release_inspection();

      final response = await pending;

      expect(response.status, FilesystemListBatchStatus.complete);
      expect(handlers.resources_released, isTrue);
    });

    test('unexpected source failure releases the inspection', () async {
      inspector.inspection_failure = StateError(
        'Unexpected inspection failure.',
      );

      handlers.open(open_request(), first);

      await expectLater(handlers.next(next_request(), first), throwsStateError);

      expect(inspector.release_count, 1);
      expect(handlers.resources_released, isTrue);
    });
  });

  group('Retirement', () {
    test('cancellation of an absent inspection is safe', () async {
      final cancelled = await handlers.cancel(cancel_request(), first);

      expect(cancelled.inspection_id, inspection_id);
      expect(handlers.resources_released, isTrue);
    });

    test('retains capacity until active inspection disposal settles', () async {
      inspector.block_inspection();

      handlers.open(open_request(), first);
      handlers.open(open_request(id: 'other'), first);

      final pending = handlers.next(next_request(), first);

      final failure = expectLater(pending, throwsStateError);

      await inspector.inspection_started.future;

      final retirement = handlers.cancel(cancel_request(), first);

      expect(handlers.active_count, 2);

      expect(
        () => handlers.open(open_request(id: 'replacement'), first),
        throwsStateError,
      );

      inspector.release_inspection();

      await retirement;
      await failure;

      expect(inspector.release_count, 1);
      expect(handlers.active_count, 1);

      handlers.open(open_request(id: 'replacement'), first);

      expect(handlers.active_count, 2);
    });

    test('idle expiration releases unused admission capacity', () async {
      final expiring = FilesystemListHandlers(
        application: FilesystemApplication(
          target_id: target_id,
          inspector: inspector,
        ),
        idle_timeout: const Duration(milliseconds: 30),
      );

      addTearDown(expiring.close);

      expiring.open(open_request(), first);

      await _wait_until(() => expiring.resources_released);

      expect(inspector.enumeration_count, 0);

      await expectLater(expiring.next(next_request(), first), throwsStateError);
    });

    test('advancement expiration initiates retirement', () async {
      final expiring = FilesystemListHandlers(
        application: FilesystemApplication(
          target_id: target_id,
          inspector: inspector,
        ),
        advancement_timeout: const Duration(milliseconds: 30),
      );

      addTearDown(() async {
        inspector.release_inspection();

        await expiring.close();
      });

      inspector.block_inspection();

      expiring.open(open_request(), first);

      final pending = expiring.next(next_request(), first);

      final failure = expectLater(pending, throwsStateError);

      await inspector.inspection_started.future;

      // Allow the advancement deadline to expire while the
      // inspection operation remains deliberately blocked.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(expiring.active_count, 1);

      inspector.release_inspection();

      await failure;

      expect(inspector.release_count, 1);
      expect(expiring.resources_released, isTrue);
    });

    test('host closure permanently prohibits further admission', () async {
      handlers.open(open_request(), first);
      handlers.open(open_request(), second);

      await handlers.close();

      expect(handlers.resources_released, isTrue);

      expect(() => handlers.open(open_request(), first), throwsStateError);
    });
  });
}

/// Waits for the asynchronous resource [condition] to become true.
///
/// Throws [TimeoutException] when resource disposal fails to settle
/// within the test deadline.
Future<void> _wait_until(bool Function() condition) async {
  final elapsed = Stopwatch()..start();

  const deadline = Duration(seconds: 5);
  const interval = Duration(milliseconds: 5);

  while (!condition()) {
    if (elapsed.elapsed >= deadline) {
      throw TimeoutException(
        'Inspection lifecycle failed to settle.',
        deadline,
      );
    }

    await Future<void>.delayed(interval);
  }
}

/// Supplies deterministic filesystem observations and disposal barriers.
final class _ControlledInspector implements TargetInspector {
  /// Number of native enumeration lifecycles initiated.
  int enumeration_count = 0;

  /// Number of enumeration lifecycles released.
  int release_count = 0;

  /// Number of child inspections initiated.
  int inspection_count = 0;

  /// Signals entry into a child inspection.
  final Completer<void> inspection_started = Completer<void>();

  /// Optional controlled inspection suspension.
  Completer<void>? _barrier;

  /// Optional unexpected failure produced by child inspection.
  Object? inspection_failure;

  /// Suspends subsequent child inspection until explicitly released.
  void block_inspection() {
    _barrier = Completer<void>();
  }

  /// Releases the controlled child inspection suspension.
  void release_inspection() {
    final barrier = _barrier;

    if (barrier != null && !barrier.isCompleted) {
      barrier.complete();
    }
  }

  /// Enumerates one deterministic child of [path].
  ///
  /// Records disposal when enumeration completes or is cancelled.
  @override
  Stream<TargetPath> list_directory(TargetPath path) async* {
    enumeration_count++;

    try {
      yield TargetPath('${path.value}/example.txt');
    } finally {
      release_count++;
    }
  }

  /// Returns a controlled observation of [path].
  ///
  /// An active barrier delays completion. Configured failures propagate.
  @override
  Future<FilesystemEntry> inspect(TargetPath path) async {
    inspection_count++;

    if (!inspection_started.isCompleted) {
      inspection_started.complete();
    }

    await _barrier?.future;

    final failure = inspection_failure;

    if (failure != null) {
      throw failure;
    }

    return FilesystemEntry(
      path: path,
      kind: FilesystemEntryKind.regularFile,
      metadata: FilesystemMetadata(),
    );
  }

  /// Rejects unexpected inspection [invocation] operations.
  @override
  Never noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'Unexpected target operation: ${invocation.memberName}',
    );
  }
}

/// Supplies an independently owned authenticated session lifecycle.
final class _TestSession implements MessageSession {
  /// Trusted peer identity shared by independent test sessions.
  @override
  String get os_user_id => 'trusted-owner';

  /// Retained communication termination signal.
  final Completer<void> _completion = Completer<void>();

  /// Completion of the controlled session lifecycle.
  @override
  Future<void> get done => _completion.future;

  /// Terminates the controlled session.
  @override
  Future<void> close() {
    if (!_completion.isCompleted) {
      _completion.complete();
    }

    return done;
  }

  /// Rejects outgoing application [request] execution.
  @override
  Future<R> request<R extends Response>(Request<R> request) async {
    throw UnsupportedError('Unexpected outgoing request.');
  }
}
