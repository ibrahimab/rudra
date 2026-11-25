import '../messaging/protocol/length_prefixed_framing.dart';
import 'pending_requests.dart';
import 'serialized_writer.dart';

/// Defines the resource limits and request deadline of a message session.
///
/// Configuration is immutable and may be shared by independently
/// executing sessions. Each session maintains its own resource counts
/// and applies these limits independently.
///
/// Configuration values are validated when a session is opened.
///
/// Example:
/// ```dart
/// const options = MessageSessionOptions(
///   maximum_pending: 16,
///   request_timeout: Duration(seconds: 15),
/// );
/// ```
final class MessageSessionOptions {
  /// Creates immutable session execution configuration.
  ///
  /// [maximum_frame_size] limits the encoded envelope size in bytes,
  /// excluding its framing header.
  ///
  /// [maximum_pending] limits outstanding outgoing requests.
  /// [maximum_incoming] limits concurrently executing incoming requests.
  /// [maximum_outstanding] limits active and queued outbound frames.
  /// [request_timeout] defines the deadline of an outgoing request,
  /// including time spent awaiting transport transmission.
  ///
  /// Construction acquires no communication resources.
  const MessageSessionOptions({
    this.maximum_frame_size = LengthPrefixedFraming.default_maximum_frame_size,
    this.maximum_pending = PendingRequests.default_maximum_pending,
    this.maximum_incoming = default_maximum_incoming,
    this.maximum_outstanding = SerializedWriter.default_maximum_outstanding,
    this.request_timeout = PendingRequests.default_request_timeout,
  });

  /// Default maximum number of concurrent incoming request handlers.
  static const int default_maximum_incoming = 32;

  /// Maximum encoded envelope size, excluding the framing header.
  final int maximum_frame_size;

  /// Maximum number of outstanding outgoing requests.
  final int maximum_pending;

  /// Maximum number of concurrently executing incoming handlers.
  final int maximum_incoming;

  /// Maximum combined number of active and queued outbound frames.
  final int maximum_outstanding;

  /// Deadline applied to each outgoing request.
  final Duration request_timeout;
}
