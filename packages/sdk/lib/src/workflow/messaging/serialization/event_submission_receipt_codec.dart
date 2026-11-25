import '../../event_submission_receipt.dart';

/// Serializes durable workflow submission receipts.
///
/// Preserves event and correlation identifiers independently
/// of communication request identities.
///
/// This codec describes a nested application payload rather
/// than an independently exchanged communication message.
///
/// Example:
/// ```dart
/// const codec = EventSubmissionReceiptCodec();
///
/// final payload = codec.encode(receipt);
/// final restored = codec.decode(payload);
///
/// print(restored.event_id);
/// ```
final class EventSubmissionReceiptCodec {
  /// Creates the stateless receipt codec.
  const EventSubmissionReceiptCodec();

  /// Converts [receipt] into its structured representation.
  ///
  /// Returns the original event and correlation identifiers.
  Map<String, Object?> encode(EventSubmissionReceipt receipt) {
    return {
      'event_id': receipt.event_id,
      'correlation_id': receipt.correlation_id,
    };
  }

  /// Reconstructs a durable submission receipt from [payload].
  ///
  /// Returns a validated receipt preserving both identifiers.
  ///
  /// Throws [FormatException] for malformed payloads,
  /// unexpected fields or invalid identifiers.
  EventSubmissionReceipt decode(Object? payload) {
    if (payload is! Map<String, Object?> || payload.length != 2) {
      throw const FormatException(
        'Invalid workflow submission receipt payload.',
      );
    }

    final event_id = payload['event_id'];
    final correlation_id = payload['correlation_id'];

    if (event_id is! String || correlation_id is! String) {
      throw const FormatException(
        'Invalid workflow submission receipt identifiers.',
      );
    }

    try {
      return EventSubmissionReceipt(
        event_id: event_id,
        correlation_id: correlation_id,
      );
    } on ArgumentError {
      throw const FormatException(
        'Invalid workflow submission receipt identifiers.',
      );
    }
  }
}
