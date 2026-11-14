/// Acknowledgment that a workflow request was durably accepted.
///
/// Receipt creation does not establish workflow creation,
/// execution, authorization, or successful domain processing.
///
/// [event_id] identifies the accepted submission.
/// [correlation_id] links subsequent processing outcomes.
///
/// A durable submission adapter must return this receipt only
/// after the corresponding acceptance transaction commits.
///
/// Example:
/// ```dart
/// final receipt = EventSubmissionReceipt(
///   event_id: 'event-001',
///   correlation_id: 'correlation-001',
/// );
/// ```
final class EventSubmissionReceipt {
  /// Creates a validated submission acknowledgment.
  ///
  /// Identifiers must be nonblank and preserve their spelling.
  ///
  /// Throws [ArgumentError] for invalid identifiers.
  EventSubmissionReceipt({
    required String event_id,
    required String correlation_id,
  })  : event_id = _require_id(event_id, 'event_id'),
        correlation_id = _require_id(
          correlation_id,
          'correlation_id',
        );

  /// Stable identity of the durably accepted submission.
  final String event_id;

  /// Identity used to correlate processing and outcome events.
  final String correlation_id;

  /// Validates an identifier without modifying it.
  static String _require_id(String value, String name) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(
        value,
        name,
        'Identifier must not be blank.',
      );
    }

    return value;
  }
}
