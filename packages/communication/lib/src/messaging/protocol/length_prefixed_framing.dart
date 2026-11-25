import 'dart:math';
import 'dart:typed_data';

import 'protocol_exception.dart';

/// Encodes and incrementally decodes length-prefixed binary frames.
///
/// Each frame contains an unsigned, big-endian four-byte length
/// header followed by the declared number of payload bytes.
///
/// Framing remains independent of the payload's serialization format
/// and the transport mechanism carrying the encoded frames.
///
/// Example:
/// ```dart
/// final framing = LengthPrefixedFraming();
/// final frame = framing.encode(Uint8List.fromList([1, 2, 3]));
///
/// await for (final payload in framing.decode(Stream.value(frame))) {
///   assert(payload.length == 3);
/// }
/// ```
final class LengthPrefixedFraming {
  /// Creates framing with the supplied [maximum_frame_size].
  ///
  /// The limit applies to payload bytes and excludes the frame header.
  ///
  /// Throws [ArgumentError] when the limit cannot be represented
  /// by the protocol's unsigned length header or is not positive.
  ///
  /// Construction does not allocate frame buffers or acquire
  /// transport resources.
  LengthPrefixedFraming({
    this.maximum_frame_size = default_maximum_frame_size,
  }) {
    if (maximum_frame_size <= 0 || maximum_frame_size > _maximum_wire_length) {
      throw ArgumentError.value(
        maximum_frame_size,
        'maximum_frame_size',
        'Invalid maximum frame size.',
      );
    }
  }

  /// Default maximum payload size of one mebibyte.
  static const int default_maximum_frame_size = 1024 * 1024;

  /// Number of bytes occupied by the unsigned length header.
  static const int _header_size = 4;

  /// Largest payload length representable by the wire header.
  static const int _maximum_wire_length = 0xffffffff;

  /// Maximum permitted payload size in bytes.
  final int maximum_frame_size;

  /// Encodes the supplied [payload] as one complete frame.
  ///
  /// Returns an independent byte buffer containing the length
  /// header followed by the payload.
  ///
  /// Throws [ProtocolException] when the payload is empty or
  /// exceeds the configured maximum frame size.
  Uint8List encode(Uint8List payload) {
    _validate_length(payload.length);

    final frame = Uint8List(_header_size + payload.length);

    ByteData.sublistView(frame).setUint32(0, payload.length, Endian.big);

    frame.setRange(_header_size, frame.length, payload);

    return frame;
  }

  /// Incrementally reconstructs frames from incoming [chunks].
  ///
  /// Returns a single-subscription stream of complete payloads.
  /// Transport chunk boundaries need not match frame boundaries.
  ///
  /// Each decoding invocation maintains independent state and
  /// subscribes to the incoming stream when consumption begins.
  /// Cancellation propagates to the underlying stream subscription.
  ///
  /// Throws [ProtocolException] through the returned stream for
  /// invalid lengths or incomplete frames at the end of input.
  /// Incoming transport errors propagate without reclassification.
  ///
  /// Retains at most one partially assembled frame, the header
  /// buffer and the current incoming transport chunk.
  Stream<Uint8List> decode(Stream<Uint8List> chunks) async* {
    final header = Uint8List(_header_size);

    var header_offset = 0;
    var payload_offset = 0;

    Uint8List? payload;

    await for (final chunk in chunks) {
      var chunk_offset = 0;

      while (chunk_offset < chunk.length) {
        if (payload == null) {
          final header_count = min(
            _header_size - header_offset,
            chunk.length - chunk_offset,
          );

          header.setRange(
            header_offset,
            header_offset + header_count,
            chunk,
            chunk_offset,
          );

          header_offset += header_count;
          chunk_offset += header_count;

          if (header_offset < _header_size) {
            continue;
          }

          final length = ByteData.sublistView(header).getUint32(0, Endian.big);

          // Validate peer-controlled lengths before allocating
          // the corresponding payload buffer.
          _validate_length(length);

          payload = Uint8List(length);
          payload_offset = 0;
          header_offset = 0;
        }

        final payload_count = min(
          payload.length - payload_offset,
          chunk.length - chunk_offset,
        );

        payload.setRange(
          payload_offset,
          payload_offset + payload_count,
          chunk,
          chunk_offset,
        );

        payload_offset += payload_count;
        chunk_offset += payload_count;

        if (payload_offset == payload.length) {
          final complete = payload;

          // Release assembly state before handing ownership of
          // the completed payload to the downstream consumer.
          payload = null;
          payload_offset = 0;

          yield complete;
        }
      }
    }

    // Stream termination is valid only at a complete frame boundary.
    if (header_offset != 0 || payload != null) {
      throw const ProtocolException(
        ProtocolErrorCode.incomplete_frame,
        'Incoming stream ended before the frame was complete.',
      );
    }
  }

  /// Validates [length] against the configured payload limits.
  ///
  /// Throws [ProtocolException] for an empty or oversized frame.
  void _validate_length(int length) {
    if (length <= 0 || length > maximum_frame_size) {
      throw const ProtocolException(
        ProtocolErrorCode.invalid_frame_length,
        'Frame length violates configured limits.',
      );
    }
  }
}
