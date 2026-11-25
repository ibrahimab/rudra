import 'dart:convert';
import 'dart:typed_data';

import 'envelope_encoding.dart';
import 'message_envelope.dart';
import 'protocol_exception.dart';

/// Encodes communication envelopes as strict UTF-8 JSON.
///
/// JSON serialization preserves the protocol envelope independently
/// of application message codecs and transport framing.
///
/// Example:
/// ```dart
/// const encoding = JsonEnvelopeEncoding();
/// final bytes = encoding.encode(envelope);
/// final decoded = encoding.decode(bytes);
/// ```
final class JsonEnvelopeEncoding implements EnvelopeEncoding {
  /// Creates a stateless JSON envelope encoder.
  ///
  /// Construction does not acquire communication resources.
  const JsonEnvelopeEncoding();

  /// Required number of fields in a version 1 envelope.
  static const int _envelope_field_count = 5;

  /// Serializes [envelope] as UTF-8 JSON.
  ///
  /// Returns an independent byte representation without framing.
  /// Payloads must contain JSON-compatible structured values.
  ///
  /// Throws [ProtocolException] for invalid envelopes or
  /// unsupported payload representations.
  @override
  Uint8List encode(MessageEnvelope envelope) {
    envelope.validate();

    try {
      final json = jsonEncode(
        {
          'protocol_version': envelope.protocol_version,
          'kind': envelope.kind.wire_value,
          'request_id': envelope.request_id,
          'message_type': envelope.message_type,
          'payload': envelope.payload,
        },
        toEncodable: (_) {
          // Application codecs, rather than implicit toJson()
          // methods, own conversion into structured payloads.
          throw const FormatException('Unsupported structured payload value.');
        },
      );

      return utf8.encode(json);
    } on JsonUnsupportedObjectError {
      throw const ProtocolException(
        ProtocolErrorCode.invalid_encoding,
        'Envelope contains unsupported JSON values.',
      );
    }
  }

  /// Decodes [bytes] as one UTF-8 JSON communication envelope.
  ///
  /// Returns an envelope validated against the supported protocol
  /// version, required fields and message metadata constraints.
  ///
  /// Throws [ProtocolException] for malformed UTF-8, malformed JSON,
  /// unsupported versions or invalid envelope representations.
  @override
  MessageEnvelope decode(Uint8List bytes) {
    final Object? decoded;

    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on FormatException {
      throw const ProtocolException(
        ProtocolErrorCode.invalid_encoding,
        'Envelope contains invalid UTF-8 or JSON.',
      );
    }

    if (decoded is! Map<String, Object?>) {
      throw const ProtocolException(
        ProtocolErrorCode.invalid_envelope,
        'Envelope must contain a JSON object.',
      );
    }

    final version = decoded['protocol_version'];

    if (version is! int) {
      throw const ProtocolException(
        ProtocolErrorCode.invalid_envelope,
        'Envelope contains an invalid protocol version.',
      );
    }

    if (version != MessageEnvelope.current_version) {
      throw const ProtocolException(
        ProtocolErrorCode.unsupported_version,
        'Unsupported communication protocol version.',
      );
    }

    final kind = decoded['kind'];
    final request_id = decoded['request_id'];
    final message_type = decoded['message_type'];

    // A null payload is valid, but an absent payload field is not.
    // Validate the complete version-specific envelope structure.
    if (decoded.length != _envelope_field_count ||
        !decoded.containsKey('payload') ||
        kind is! String ||
        request_id is! String ||
        message_type is! String) {
      throw const ProtocolException(
        ProtocolErrorCode.invalid_envelope,
        'Envelope contains invalid or missing fields.',
      );
    }

    return MessageEnvelope(
      kind: _decode_kind(kind),
      request_id: request_id,
      message_type: message_type,
      payload: decoded['payload'],
    );
  }

  /// Resolves the message kind represented by [wire_value].
  ///
  /// Returns the corresponding protocol message kind.
  /// Throws [ProtocolException] for an unsupported wire value.
  MessageKind _decode_kind(String wire_value) {
    for (final kind in MessageKind.values) {
      if (kind.wire_value == wire_value) {
        return kind;
      }
    }

    throw const ProtocolException(
      ProtocolErrorCode.invalid_envelope,
      'Unknown envelope message kind.',
    );
  }
}
