import 'contracts/transport.dart';

/// Selects the transport for an explicit client connection attempt.
///
/// ### Example
///
/// ```dart
/// final session = await communication.connect(
///   const ConnectionParams(
///     transport: MacOsUnixTransport(socket_path: '/private/tmp/example/rudra.sock'),
///   ),
/// );
/// try {
///   await session.request(const EchoRequest('Hello'));
/// } finally {
///   await session.close();
///   await communication.done;
/// }
/// ```
final class ConnectionParams {
  /// Uses native local connectivity when [transport] is omitted.
  ///
  /// An explicit transport owns its endpoint configuration and authentication.
  /// It must support independent attempts if reused for reconnection.
  const ConnectionParams({this.transport});

  /// Optional configured transport for the next connection lifecycle.
  final Transport? transport;
}
