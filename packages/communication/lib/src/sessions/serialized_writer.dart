import 'dart:async';
import 'dart:typed_data';

import 'message_session_exception.dart';

/// Coordinates bounded, serialized outbound frame writes.
///
/// Maintains one active transport write at a time and preserves
/// the submission order of accepted frames.
///
/// The writer borrows a sending capability from its owning session.
/// Native connection ownership remains with that session.
///
/// Example:
/// ```dart
/// final writer = SerializedWriter(send: connection.send);
///
/// await writer.write(frame);
///
/// writer.stop();
/// await connection.close();
/// await writer.done;
/// ```
final class SerializedWriter {
  /// Creates a writer using the supplied [send] capability.
  ///
  /// [maximum_outstanding] limits the combined number of active
  /// and queued writes.
  ///
  /// Construction performs no transport operations.
  /// Throws [ArgumentError] for non-positive capacity.
  SerializedWriter({
    required Future<void> Function(Uint8List) send,
    this.maximum_outstanding = default_maximum_outstanding,
  }) : _send = send {
    if (maximum_outstanding <= 0) {
      throw ArgumentError.value(
        maximum_outstanding,
        'maximum_outstanding',
        'Write capacity must be positive.',
      );
    }
  }

  /// Default maximum number of active and queued writes.
  static const int default_maximum_outstanding = 64;

  /// Maximum number of outstanding writes retained by this writer.
  final int maximum_outstanding;

  /// Borrowed capability performing one transport write.
  final Future<void> Function(Uint8List) _send;

  /// Retained completion of the serialized write chain.
  ///
  /// Individual write failures are reported through their own
  /// futures rather than poisoning the internal scheduling chain.
  Future<void> _tail = Future<void>.value();

  /// Number of writes accepted but not yet completed.
  int _outstanding = 0;

  /// Whether additional transport writes have been prohibited.
  bool _is_stopped = false;

  /// Original transport failure, when execution stopped unsuccessfully.
  Object? _failure;

  /// Local stack associated with the original transport failure.
  StackTrace? _failure_stack;

  /// Number of active and queued writes.
  int get outstanding => _outstanding;

  /// Whether the writer has permanently stopped accepting writes.
  bool get is_stopped => _is_stopped;

  /// Completion of all writes accepted up to the time of access.
  ///
  /// After [stop], this represents the final writer drain.
  /// Individual write failures remain observable through the
  /// futures returned by [write].
  Future<void> get done => _tail;

  /// Queues [frame] for ordered transport transmission.
  ///
  /// Ownership of the frame buffer transfers to the writer when
  /// accepted. The caller must not subsequently modify that buffer.
  ///
  /// Returns after the underlying sending capability completes.
  ///
  /// Completes with [MessageSessionException] when the writer has
  /// stopped or its outstanding capacity has been exhausted.
  ///
  /// Transport failures propagate to the returned future and stop
  /// subsequent transport writes.
  Future<void> write(Uint8List frame) {
    if (_is_stopped) {
      return Future<void>.error(
        _failure ??
            const MessageSessionException(
              MessageSessionErrorCode.session_closed,
            ),
        _failure_stack,
      );
    }

    if (_outstanding >= maximum_outstanding) {
      return Future<void>.error(
        const MessageSessionException(
          MessageSessionErrorCode.capacity_exceeded,
        ),
      );
    }

    final completion = Completer<void>();

    // Reserve capacity synchronously, before scheduling execution.
    _outstanding++;

    _tail = _tail.then<void>((_) async {
      try {
        // A previous write or session shutdown may have stopped
        // execution while this frame was waiting in the queue.
        if (_is_stopped) {
          completion.completeError(
            _failure ??
                const MessageSessionException(
                  MessageSessionErrorCode.session_closed,
                ),
            _failure_stack,
          );

          return;
        }

        await _send(frame);

        completion.complete();
      } catch (error, stack) {
        // Never initiate another transport write after a failed send.
        _failure ??= error;
        _failure_stack ??= stack;
        _is_stopped = true;

        completion.completeError(error, stack);
      } finally {
        _outstanding--;
      }
    });

    return completion.future;
  }

  /// Permanently stops admission and execution of queued writes.
  ///
  /// An already active transport write is allowed to settle.
  /// The owning session remains responsible for closing its
  /// connection to unblock native transmission when necessary.
  ///
  /// Await [done] after transport shutdown to confirm writer drain.
  /// Repeated calls have no additional effect.
  void stop() {
    _is_stopped = true;
  }
}
