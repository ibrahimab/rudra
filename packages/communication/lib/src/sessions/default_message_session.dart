import 'dart:async';
import 'dart:typed_data';

import '../messaging/message.dart';
import '../messaging/message_codec_registry.dart';
import '../messaging/protocol/envelope_encoding.dart';
import '../messaging/protocol/json_envelope_encoding.dart';
import '../messaging/protocol/length_prefixed_framing.dart';
import '../messaging/protocol/message_envelope.dart';
import '../messaging/protocol/protocol_exception.dart';
import '../messaging/request_handler_registry.dart';
import '../transport/contracts/transport_connection.dart';
import 'message_session.dart';
import 'message_session_exception.dart';
import 'message_session_options.dart';
import 'pending_requests.dart';
import 'serialized_writer.dart';

/// Executes typed bidirectional messaging over an authenticated connection.
///
/// Owns incoming protocol processing, outgoing request correlation,
/// serialized transmission and communication resource disposal.
///
/// Registered application handlers execute independently of incoming
/// frame processing, allowing either peer to initiate requests while
/// previously received application requests remain outstanding.
///
/// Example:
/// ```dart
/// final session = DefaultMessageSession.open(
///   connection: connection,
///   codecs: codecs,
///   handlers: handlers,
/// );
///
/// try {
///   final response = await session.request(
///     const EchoRequest('Hello'),
///   );
/// } finally {
///   try {
///     await session.close();
///   } finally {
///     await session.handlers_done;
///   }
/// }
/// ```
final class DefaultMessageSession implements MessageSession {
  /// Constructs the intrinsic components of a message session.
  ///
  /// [connection] supplies the authenticated transport capability.
  /// [codecs] and [handlers] supply frozen messaging configuration.
  /// [options] defines the session's execution limits.
  /// [encoding] optionally substitutes the default envelope encoder.
  ///
  /// Throws [StateError] for incompatible or mutable registration
  /// configuration and [ArgumentError] for invalid execution limits.
  ///
  /// Construction does not subscribe to incoming transport data.
  DefaultMessageSession._({
    required TransportConnection connection,
    required MessageCodecRegistry codecs,
    required RequestHandlerRegistry handlers,
    required MessageSessionOptions options,
    EnvelopeEncoding? encoding,
  }) : _connection = connection,
       _codecs = codecs,
       _handlers = handlers,
       _encoding = encoding ?? const JsonEnvelopeEncoding(),
       _framing = LengthPrefixedFraming(
         maximum_frame_size: options.maximum_frame_size,
       ),
       _maximum_incoming = options.maximum_incoming {
    if (!codecs.is_frozen || !handlers.is_frozen) {
      throw StateError('Messaging configuration must be frozen.');
    }

    // Revalidate the relationship between the two frozen registries.
    // A handler registry cannot be rebound to different codecs.
    handlers.freeze(codecs: codecs);

    if (_maximum_incoming <= 0) {
      throw ArgumentError.value(
        _maximum_incoming,
        'maximum_incoming',
        'Incoming request capacity must be positive.',
      );
    }

    _pending = PendingRequests(
      maximum_pending: options.maximum_pending,
      request_timeout: options.request_timeout,
      on_timeout: _on_timeout,
    );

    _writer = SerializedWriter(
      send: connection.send,
      maximum_outstanding: options.maximum_outstanding,
    );

    // Termination may occur before an external owner awaits done.
    // Retain the original result without an unhandled future error.
    _completion.future.ignore();
  }

  /// Opens a message session over the supplied [connection].
  ///
  /// [codecs] and [handlers] must contain compatible frozen
  /// messaging configuration.
  ///
  /// [options] optionally supplies execution limits and deadlines.
  /// [encoding] optionally substitutes the default wire encoder.
  ///
  /// Returns an executing session that owns the connection.
  /// Successful opening transfers connection ownership to the
  /// returned session.
  ///
  /// If opening throws, connection ownership remains with the caller.
  static DefaultMessageSession open({
    required TransportConnection connection,
    required MessageCodecRegistry codecs,
    required RequestHandlerRegistry handlers,
    MessageSessionOptions options = const MessageSessionOptions(),
    EnvelopeEncoding? encoding,
  }) {
    final session = DefaultMessageSession._(
      connection: connection,
      codecs: codecs,
      handlers: handlers,
      options: options,
      encoding: encoding,
    );

    session._start();

    return session;
  }

  /// Authenticated connection owned by this session.
  final TransportConnection _connection;

  /// Shared, frozen message codec configuration.
  final MessageCodecRegistry _codecs;

  /// Shared, frozen application handler configuration.
  final RequestHandlerRegistry _handlers;

  /// Envelope serialization capability used by this session.
  final EnvelopeEncoding _encoding;

  /// Session-owned bounded frame encoding and decoding.
  final LengthPrefixedFraming _framing;

  /// Maximum number of concurrently executing incoming handlers.
  final int _maximum_incoming;

  /// Session-owned outgoing request correlation state.
  late final PendingRequests _pending;

  /// Session-owned serialized outbound writer.
  late final SerializedWriter _writer;

  /// Subscription to complete incoming protocol frames.
  late final StreamSubscription<Uint8List> _incoming;

  /// Final communication lifecycle completion.
  final Completer<void> _completion = Completer<void>();

  /// Completion of all admitted application handlers after termination.
  final Completer<void> _handlers_completion = Completer<void>();

  /// Highest accepted request identifier in the incoming direction.
  BigInt _last_incoming_request_id = BigInt.zero;

  /// Number of admitted incoming requests still being processed.
  int _active_handlers = 0;

  /// Retained resource disposal result.
  ///
  /// A non-null value also establishes that termination has begun.
  Future<void>? _closing;

  /// Trusted operating-system identity of the connected peer.
  @override
  String get os_user_id => _connection.os_user_id;

  /// Final communication lifecycle result.
  ///
  /// Completes after communication resource disposal, reporting
  /// the terminal execution or resource disposal failure if present.
  @override
  Future<void> get done => _completion.future;

  /// Completion of all application handlers admitted by this session.
  ///
  /// Completes once termination has begun and every admitted
  /// application handler has finished.
  ///
  /// The owning communication coordinator must await this completion
  /// before releasing application resources used by those handlers.
  ///
  /// Application handlers must not await their own drain completion.
  Future<void> get handlers_done => _handlers_completion.future;

  /// Starts independent incoming protocol processing.
  ///
  /// Subscribes to the authenticated connection's incoming stream
  /// exactly once.
  void _start() {
    _incoming = _framing
        .decode(_connection.incoming)
        .listen(_on_frame, onError: _on_read_error, onDone: _on_read_done);
  }

  /// Sends [request] and awaits its correlated response of type [R].
  ///
  /// Returns the validated application response independently of
  /// transport write completion.
  ///
  /// Local configuration, encoding and capacity failures reject the
  /// request without terminating otherwise healthy communication.
  ///
  /// Transport and protocol failures terminate the session.
  /// Request deadline expiration also initiates session termination.
  ///
  /// Communication does not retry failed application operations.
  @override
  Future<R> request<R extends Response>(Request<R> request) async {
    _require_outgoing_capacity();

    final expected_response_type = _codecs.response_type_for(request);
    final encoded = _codecs.encode(request);

    // Correlation state must exist before transmission begins.
    final pending = _pending.register<R>(
      expected_response_type: expected_response_type,
    );

    try {
      final frame = _encode_frame(
        MessageEnvelope(
          kind: MessageKind.request,
          request_id: pending.request_id,
          message_type: encoded.type_id,
          payload: encoded.payload,
        ),
      );

      _require_writer_capacity();

      // Observe transmission independently so a stalled write cannot
      // prevent the request deadline from completing its caller.
      unawaited(_observe_write(frame));
    } catch (error, stack) {
      // Local submission failed before admission to the writer.
      // No remote response is expected for this identifier.
      _pending.fail_local(pending.request_id, error, stack);
    }

    return pending.response;
  }

  /// Verifies that another outgoing request can be admitted.
  ///
  /// Throws [MessageSessionException] after termination or when
  /// outgoing correlation or transmission capacity is exhausted.
  void _require_outgoing_capacity() {
    _require_writer_capacity();

    if (_pending.count >= _pending.maximum_pending) {
      throw const MessageSessionException(
        MessageSessionErrorCode.capacity_exceeded,
      );
    }
  }

  /// Verifies that the session can accept another outbound frame.
  ///
  /// Throws [MessageSessionException] after termination or when
  /// outbound writer capacity is exhausted.
  void _require_writer_capacity() {
    if (_closing != null || _writer.is_stopped) {
      throw const MessageSessionException(
        MessageSessionErrorCode.session_closed,
      );
    }

    if (_writer.outstanding >= _writer.maximum_outstanding) {
      throw const MessageSessionException(
        MessageSessionErrorCode.capacity_exceeded,
      );
    }
  }

  /// Encodes [envelope] into an independent, bounded transport frame.
  ///
  /// Returns the complete length-prefixed wire representation.
  /// Encoding and framing failures propagate to the caller.
  Uint8List _encode_frame(MessageEnvelope envelope) {
    return _framing.encode(_encoding.encode(envelope));
  }

  /// Encodes [message] into a frame with the supplied [kind]
  /// and correlated [request_id].
  ///
  /// Returns an independently encoded transport frame.
  /// Message codec, envelope and framing failures propagate.
  Uint8List _encode_message({
    required MessageKind kind,
    required String request_id,
    required Message message,
  }) {
    final encoded = _codecs.encode(message);

    return _encode_frame(
      MessageEnvelope(
        kind: kind,
        request_id: request_id,
        message_type: encoded.type_id,
        payload: encoded.payload,
      ),
    );
  }

  /// Encodes a sanitized remote failure for [request_id].
  ///
  /// [code] identifies the communication-owned failure category.
  /// Returns the bounded failure frame without application diagnostics.
  Uint8List _encode_failure(String request_id, RequestFailureCode code) {
    return _encode_frame(
      MessageEnvelope.failure(request_id: request_id, code: code),
    );
  }

  /// Submits [frame] to the serialized writer and observes its result.
  ///
  /// Transport write failures or failed reply admission initiate
  /// session termination. Errors occurring after termination begins
  /// cannot replace the original termination cause.
  ///
  /// Returns after the accepted write settles or admission fails.
  Future<void> _observe_write(Uint8List frame) async {
    try {
      await _writer.write(frame);
    } catch (error, stack) {
      _terminate(error, stack).ignore();
    }
  }

  /// Processes one complete incoming [frame].
  ///
  /// Decodes and validates the envelope before routing it according
  /// to its communication delivery semantics.
  ///
  /// Protocol failures terminate the affected session.
  /// Incoming request dispatch does not block frame processing.
  void _on_frame(Uint8List frame) {
    if (_closing != null) {
      return;
    }

    try {
      final envelope = _decode_envelope(frame);

      switch (envelope.kind) {
        case MessageKind.request:
          _accept_request(envelope);
          break;

        case MessageKind.response:
          _accept_response(envelope);
          break;

        case MessageKind.error:
          _accept_failure(envelope);
          break;
      }
    } catch (error, stack) {
      _terminate(error, stack).ignore();
    }
  }

  /// Reconstructs and validates an envelope from [frame].
  ///
  /// Returns a structurally valid communication envelope.
  /// Throws [ProtocolException] for invalid encoded protocol data.
  MessageEnvelope _decode_envelope(Uint8List frame) {
    try {
      final envelope = _encoding.decode(frame);

      envelope.validate();

      return envelope;
    } on ProtocolException {
      rethrow;
    } catch (_) {
      throw const ProtocolException(
        ProtocolErrorCode.invalid_encoding,
        'Unable to decode incoming message envelope.',
      );
    }
  }

  /// Reconstructs the application object contained in [envelope].
  ///
  /// Returns the registered concrete message instance.
  /// Throws [ProtocolException] when the message type or payload
  /// violates the configured application message contract.
  Message _decode_message(MessageEnvelope envelope) {
    try {
      return _codecs.decode(envelope.message_type, envelope.payload);
    } catch (_) {
      // Codec diagnostics may contain remote payload data.
      // Classify the failure without retaining that representation.
      throw const ProtocolException(
        ProtocolErrorCode.invalid_message,
        'Unable to decode registered application message.',
      );
    }
  }

  /// Admits the incoming request represented by [envelope].
  ///
  /// Validates monotonic request identifiers, incoming capacity
  /// and the registered application message category.
  ///
  /// Throws [ProtocolException] for a correlation, capacity or
  /// message contract violation.
  void _accept_request(MessageEnvelope envelope) {
    final request_id = BigInt.parse(envelope.request_id);

    if (request_id <= _last_incoming_request_id) {
      throw const ProtocolException(
        ProtocolErrorCode.invalid_correlation,
        'Incoming request identifier is not increasing.',
      );
    }

    if (_active_handlers >= _maximum_incoming) {
      throw const ProtocolException(
        ProtocolErrorCode.capacity_exceeded,
        'Incoming request capacity exhausted.',
      );
    }

    final message = _decode_message(envelope);

    if (message is! Request<Response> || message is Response) {
      throw const ProtocolException(
        ProtocolErrorCode.invalid_message,
        'Incoming request contains an incompatible message.',
      );
    }

    _last_incoming_request_id = request_id;

    // Reserve incoming capacity before executing application code.
    // The frame reader remains available for responses and other
    // independently admitted requests.
    _active_handlers++;

    unawaited(_serve_request(envelope.request_id, message));
  }

  /// Dispatches [request] and prepares its correlated response.
  ///
  /// [request_id] identifies the incoming communication request.
  ///
  /// Missing handlers and unexpected application execution or
  /// response encoding failures produce sanitized remote failures.
  ///
  /// Application execution remains independent of session termination.
  /// Responses are discarded if communication has already terminated.
  ///
  /// Returns after application execution and response preparation.
  Future<void> _serve_request(
    String request_id,
    Request<Response> request,
  ) async {
    try {
      final Uint8List frame;

      try {
        final response = await _handlers.dispatch(request, this);

        if (_closing != null) {
          return;
        }

        frame = response == null
            ? _encode_failure(
                request_id,
                RequestFailureCode.handler_unavailable,
              )
            : _encode_message(
                kind: MessageKind.response,
                request_id: request_id,
                message: response,
              );
      } catch (_) {
        if (_closing != null) {
          return;
        }

        // Never serialize application exceptions or stack traces.
        final failure_frame = _encode_failure(
          request_id,
          RequestFailureCode.handler_failed,
        );

        unawaited(_observe_write(failure_frame));

        return;
      }

      if (_closing == null) {
        unawaited(_observe_write(frame));
      }
    } catch (error, stack) {
      // Failure to construct even a sanitized reply means the
      // request cannot be completed through this session.
      _terminate(error, stack).ignore();
    } finally {
      _active_handlers--;

      _complete_handlers_if_drained();
    }
  }

  /// Resolves the outgoing request associated with [envelope].
  ///
  /// Validates the application response category and delegates
  /// exact response type and correlation validation to the
  /// pending request coordinator.
  ///
  /// Throws [ProtocolException] for incompatible responses or
  /// unknown request identifiers.
  void _accept_response(MessageEnvelope envelope) {
    final message = _decode_message(envelope);

    if (message is! Response || message is Request<Response>) {
      throw const ProtocolException(
        ProtocolErrorCode.invalid_message,
        'Incoming response contains an incompatible message.',
      );
    }

    _pending.complete_response(envelope.request_id, message);
  }

  /// Resolves the sanitized remote failure represented by [envelope].
  ///
  /// Completes only the associated outgoing request with an error.
  /// Other requests and the communication session remain active.
  ///
  /// Throws [ProtocolException] for unknown request identifiers.
  void _accept_failure(MessageEnvelope envelope) {
    // Envelope validation has already established the reserved
    // error representation and permitted failure codes.
    final payload = envelope.payload as Map<String, Object?>;

    final failure = RequestFailureCode.values.singleWhere(
      (code) => code.wire_value == payload['code'],
    );

    final error_code = switch (failure) {
      RequestFailureCode.handler_unavailable =>
        MessageSessionErrorCode.handler_unavailable,
      RequestFailureCode.handler_failed =>
        MessageSessionErrorCode.handler_failed,
    };

    _pending.complete_failure(
      envelope.request_id,
      MessageSessionException(error_code),
    );
  }

  /// Handles an incoming transport or framing [error].
  ///
  /// [stack] preserves its local diagnostic stack.
  /// Initiates termination without replacing an existing cause.
  void _on_read_error(Object error, StackTrace stack) {
    _terminate(error, stack).ignore();
  }

  /// Handles normal termination of the incoming transport stream.
  ///
  /// Outstanding outgoing requests fail because their responses
  /// can no longer be delivered.
  void _on_read_done() {
    _terminate().ignore();
  }

  /// Handles an expired outgoing request deadline.
  ///
  /// Terminates communication to prevent late responses from
  /// becoming ambiguous correlation state.
  ///
  /// Application operations already executing are not cancelled.
  void _on_timeout() {
    _terminate(
      const MessageSessionException(MessageSessionErrorCode.request_timeout),
    ).ignore();
  }

  /// Terminates communication and releases session-owned resources.
  ///
  /// Returns the retained resource disposal result.
  /// Previously admitted application handlers continue independently.
  @override
  Future<void> close() => _terminate();

  /// Begins termination with the optional [cause] and diagnostic [stack].
  ///
  /// The first termination operation permanently closes request
  /// admission and establishes the communication lifecycle result.
  ///
  /// Returns the retained disposal result for all subsequent calls.
  Future<void> _terminate([Object? cause, StackTrace? stack]) {
    final closing = _closing;

    if (closing != null) {
      return closing;
    }

    final disposal = Completer<void>();

    // Publish the termination state before completing pending
    // requests or initiating asynchronous resource disposal.
    _closing = disposal.future;
    disposal.future.ignore();

    _writer.stop();

    _pending.close(
      cause ??
          const MessageSessionException(MessageSessionErrorCode.session_closed),
      stack,
    );

    _complete_handlers_if_drained();

    unawaited(_dispose(disposal, cause, stack));

    return disposal.future;
  }

  /// Releases communication resources and completes lifecycle futures.
  ///
  /// [disposal] reports resource disposal independently of execution.
  /// [cause] and [stack] identify the original terminal failure.
  ///
  /// Transport closure and incoming cancellation are initiated
  /// independently so neither prevents the other from beginning.
  ///
  /// Previously admitted application handlers are deliberately
  /// excluded from communication resource disposal.
  Future<void> _dispose(
    Completer<void> disposal,
    Object? cause,
    StackTrace? stack,
  ) async {
    try {
      try {
        await Future.wait<void>([
          Future<void>.sync(_connection.close),
          Future<void>.sync(_incoming.cancel),
        ]);
      } finally {
        // Native connection termination must settle any active
        // transmission before writer disposal can be confirmed.
        await _writer.done;
      }
    } catch (error, disposal_stack) {
      disposal.completeError(error, disposal_stack);
      _completion.completeError(error, disposal_stack);

      return;
    }

    disposal.complete();

    if (cause == null) {
      _completion.complete();
    } else {
      _completion.completeError(cause, stack);
    }
  }

  /// Completes handler draining once termination prohibits further
  /// admission and all previously admitted handlers have finished.
  ///
  /// Repeated calls have no additional effect.
  void _complete_handlers_if_drained() {
    if (_closing != null &&
        _active_handlers == 0 &&
        !_handlers_completion.isCompleted) {
      _handlers_completion.complete();
    }
  }
}
