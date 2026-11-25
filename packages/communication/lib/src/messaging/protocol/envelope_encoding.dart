import 'dart:typed_data';

import 'message_envelope.dart';
import 'protocol_exception.dart';

/// Converts communication envelopes between structured and binary
/// wire representations.
///
/// Implementations define the serialization format independently
/// of message codecs, framing and transport mechanisms.
///
/// Encoding implementations must preserve the envelope's metadata
/// and structured payload semantics.
///
/// Example:
/// ```dart
/// final bytes = encoding.encode(envelope);
/// final decoded = encoding.decode(bytes);
/// ```
abstract interface class EnvelopeEncoding {
  /// Serializes the supplied [envelope].
  ///
  /// Returns an independent byte representation suitable for framing.
  /// Throws [ProtocolException] when the envelope cannot be encoded.
  Uint8List encode(MessageEnvelope envelope);

  /// Reconstructs an envelope from the supplied [bytes].
  ///
  /// The bytes must contain exactly one encoded envelope without
  /// its transport framing header.
  ///
  /// Returns a validated envelope without retaining the input buffer.
  /// Throws [ProtocolException] for malformed or unsupported data.
  MessageEnvelope decode(Uint8List bytes);
}
