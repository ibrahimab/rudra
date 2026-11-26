/// Availability of authoritative remote application-state observation.
///
/// Synchronization status describes the observation infrastructure,
/// independently of workflow lifecycle and immutable domain state.
///
/// Example:
/// ```dart
/// if (sdk.synchronization_status ==
///     StateSynchronizationStatus.synchronized) {
///   print('Authoritative observation available');
/// }
/// ```
enum StateSynchronizationStatus {
  /// No authenticated host connection is available.
  disconnected,

  /// Connected without an admitted local state observation.
  idle,

  /// Awaiting subscription acceptance and initial verified state.
  synchronizing,

  /// Receiving verified state through an admitted subscription.
  synchronized,

  /// Retiring the remote subscription and draining admitted delivery.
  cancelling,

  /// State synchronization failed and its session is being retired.
  failed,

  /// The owning SDK observation capability has permanently closed.
  closed,
}
