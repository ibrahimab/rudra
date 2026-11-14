
/// Stable categories of event submission failure.
///
/// These failures concern accepting a request, not the eventual
/// result of workflow processing.
enum EventSubmissionErrorCode {
  /// The request could not be committed to durable storage.
  persistence_failed,

  /// An idempotency key conflicts with a different submission.
  idempotency_conflict,
}

/// Indicates that durable event submission was unsuccessful.
///
/// No successful submission acknowledgment may be returned
/// when this exception is thrown.
///
/// Business-level rejection belongs to subsequent processing.
///
/// Example:
/// ```dart
/// throw EventSubmissionException(
///   code: EventSubmissionErrorCode.persistence_failed,
///   message: 'Unable to persist the submitted event.',
/// );
/// ```
final class EventSubmissionException implements Exception {
  /// Creates a typed submission failure.
  const EventSubmissionException({
    required this.code,
    required this.message,
  });

  /// Stable failure classification.
  final EventSubmissionErrorCode code;

  /// Human-readable diagnostic explanation.
  final String message;

  @override
  String toString() {
    return 'EventSubmissionException('
        'code: ${code.name}): $message';
  }
}
