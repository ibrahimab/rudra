import '../message_type_id.dart';
import 'protocol_exception.dart';

/// Identifies the delivery semantics of a communication envelope.
///
/// Wire values remain stable independently of Dart enum names.
///
/// Example:
/// ```dart
/// assert(MessageKind.request.wire_value == 'request');
/// ```
enum MessageKind {
  /// Delivers an application request.
  request('request'),

  /// Delivers a correlated application response.
  response('response'),

  /// Reports a communication-owned request failure.
  error('error');

  /// Associates this kind with its stable [wire_value].
  const MessageKind(this.wire_value);

  /// Stable protocol representation of this message kind.
  final String wire_value;
}

/// Identifies a sanitized failure while handling a remote request.
///
/// These codes describe communication-owned failures rather than
/// expected application rejection outcomes.
///
/// Example:
/// ```dart
/// assert(RequestFailureCode.handler_failed.wire_value ==
///     'handler_failed');
/// ```
enum RequestFailureCode {
  /// No application handler is registered for the request.
  handler_unavailable('handler_unavailable'),

  /// The application handler failed unexpectedly.
  handler_failed('handler_failed');

  /// Associates this failure with its stable [wire_value].
  const RequestFailureCode(this.wire_value);

  /// Stable protocol representation of this request failure.
  final String wire_value;
}

/// Represents the protocol metadata and payload of one message.
///
/// Communication constructs envelopes independently of application
/// message objects. Envelopes remain independent of their wire
/// encoding and transport framing.
///
/// The payload is a structured value supplied by the message codec.
/// Its contents must remain stable while the envelope is being encoded.
///
/// Example:
/// ```dart
/// final envelope = MessageEnvelope(
///   kind: MessageKind.request,
///   request_id: '1',
///   message_type: 'example.echo.request.v1',
///   payload: {'value': 'Hello'},
/// );
/// ```
final class MessageEnvelope {
  /// Creates an envelope containing the supplied communication data.
  ///
  /// [kind] identifies the message's delivery semantics.
  /// [request_id] identifies the correlated request within a session.
  /// [message_type] identifies the registered wire representation.
  /// [payload] contains the structured message data.
  ///
  /// Throws [ProtocolException] when the envelope violates
  /// the current protocol's structural requirements.
  MessageEnvelope({
    required this.kind,
    required this.request_id,
    required this.message_type,
    required this.payload,
  }) {
    validate();
  }

  /// Creates a sanitized failure for the supplied [request_id].
  ///
  /// [code] identifies the communication-owned request failure.
  /// Returns an error envelope containing only its stable failure code.
  ///
  /// Throws [ProtocolException] for an invalid request identifier.
  factory MessageEnvelope.failure({
    required String request_id,
    required RequestFailureCode code,
  }) => MessageEnvelope(
    kind: MessageKind.error,
    request_id: request_id,
    message_type: communication_error_type_id,
    payload: Map<String, Object?>.unmodifiable({'code': code.wire_value}),
  );

  /// Protocol version implemented by this envelope.
  static const int current_version = 1;

  /// Permitted syntax and length of session-local request identifiers.
  static final RegExp _request_id_pattern = RegExp(r'^[1-9][0-9]{0,19}$');

  /// Version of the protocol represented by this envelope.
  int get protocol_version => current_version;

  /// Delivery semantics of the enclosed message.
  final MessageKind kind;

  /// Session-local identifier of the associated request.
  final String request_id;

  /// Stable wire identifier of the enclosed message representation.
  final String message_type;

  /// Structured application data or sanitized request failure payload.
  final Object? payload;

  /// Validates this envelope against the current protocol requirements.
  ///
  /// Revalidation before encoding protects the protocol boundary
  /// from changes to externally supplied structured payloads.
  ///
  /// Throws [ProtocolException] when the envelope is invalid.
  void validate() {
    final request_id_match = _request_id_pattern.firstMatch(request_id);

    if (request_id_match == null || request_id_match.end != request_id.length) {
      throw const ProtocolException(
        ProtocolErrorCode.invalid_envelope,
        'Invalid request identifier.',
      );
    }

    if (kind == MessageKind.error) {
      _validate_failure();
      return;
    }

    if (!is_application_message_type_id(message_type)) {
      throw const ProtocolException(
        ProtocolErrorCode.invalid_envelope,
        'Invalid application message type identifier.',
      );
    }
  }

  /// Validates the reserved representation of a request failure.
  ///
  /// Only recognized failure codes are accepted. Additional payload
  /// fields are prohibited to prevent infrastructure diagnostics
  /// from being included in protocol error responses.
  ///
  /// Throws [ProtocolException] for an invalid failure envelope.
  void _validate_failure() {
    final failure_payload = payload;

    if (message_type != communication_error_type_id ||
        failure_payload is! Map<String, Object?> ||
        failure_payload.length != 1) {
      throw const ProtocolException(
        ProtocolErrorCode.invalid_envelope,
        'Invalid request failure representation.',
      );
    }

    final code = failure_payload['code'];

    if (!RequestFailureCode.values.any(
      (failure) => failure.wire_value == code,
    )) {
      throw const ProtocolException(
        ProtocolErrorCode.invalid_envelope,
        'Unknown request failure code.',
      );
    }
  }
}
