import '../messaging/message.dart';

/// Represents an authenticated object-level communication session.
///
/// A session exchanges typed application requests and responses while
/// maintaining correlation, protocol processing and transport lifecycle
/// independently of its consumers.
///
/// Sessions support requests initiated by either connected peer.
/// Each session represents one established connection and cannot be
/// reused after termination.
///
/// Example:
/// ```dart
/// try {
///   final response = await session.request(
///     const EchoRequest('Hello'),
///   );
///
///   print(response.value);
/// } finally {
///   await session.close();
/// }
/// ```
abstract interface class MessageSession {
  /// Trusted operating-system identity of the connected peer.
  ///
  /// The identity originates from native transport authentication
  /// rather than application message payloads.
  String get os_user_id;

  /// Completion of the session's communication lifecycle.
  ///
  /// Completes after communication resources have been disposed of.
  /// Protocol, transport and resource disposal failures are reported
  /// through this future.
  ///
  /// Application request failures do not independently terminate
  /// an otherwise healthy session.
  Future<void> get done;

  /// Sends [request] and awaits its correlated response.
  ///
  /// [R] identifies the response type associated with the request.
  /// Returns the validated application response supplied by the peer.
  ///
  /// Communication maintains request identifiers and pending request
  /// state independently of the application message.
  ///
  /// Configuration, request processing, remote handler, deadline and
  /// connection termination failures complete the returned future
  /// with an error.
  ///
  /// Failed requests are not automatically retried. Communication
  /// failure does not establish whether the remote application
  /// operation executed or committed.
  Future<R> request<R extends Response>(Request<R> request);

  /// Terminates communication and releases session-owned resources.
  ///
  /// Outstanding requests are completed with a termination failure.
  /// Repeated calls return the retained resource disposal result.
  /// Resource disposal failures propagate to the caller.
  ///
  /// Closing communication does not cancel application handlers
  /// that have already started executing.
  Future<void> close();
}
