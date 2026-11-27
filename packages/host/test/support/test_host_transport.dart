import 'dart:async';

import 'package:rudra_communication/rudra_communication.dart';

/// Provides an isolated transport for host composition tests.
///
/// Records listener creation without binding native endpoints
/// or accepting real operating-system connections.
///
/// Example:
/// ```dart
/// final transport = TestHostTransport();
/// final listener = await transport.listen();
/// await listener.close();
/// ```
final class TestHostTransport implements Transport {
  /// Creates an initially inactive transport fixture.
  ///
  /// [on_close] optionally observes listener disposal before
  /// successful completion is recorded. Throwing from the callback
  /// simulates an unsuccessful listener disposal.
  TestHostTransport({void Function()? on_close}) : _on_close = on_close;

  /// Optional callback observing or rejecting listener disposal.
  final void Function()? _on_close;

  /// Number of successfully created test listeners.
  int listen_count = 0;

  /// Number of successfully disposed test listeners.
  int close_count = 0;

  /// Creates a controlled listening endpoint.
  ///
  /// Returns an idle listener with no incoming connections.
  @override
  Future<TransportListener> listen() async {
    listen_count++;

    return _TestTransportListener(() {
      // Exercise the surrounding resource ownership boundary
      // before recording successful listener disposal.
      _on_close?.call();

      close_count++;
    });
  }

  /// Rejects outbound connection establishment for this fixture.
  ///
  /// Throws [UnsupportedError] because host composition tests
  /// exercise listener and exclusive ownership lifecycles.
  @override
  Future<TransportConnection> connect() async {
    throw UnsupportedError('Outbound connectivity is outside this fixture.');
  }
}

/// Represents an idle listener owned by a composition test.
///
/// Example:
/// ```dart
/// final listener = _TestTransportListener(() {});
/// await listener.close();
/// ```
final class _TestTransportListener implements TransportListener {
  /// Creates a listener with its disposal callback.
  _TestTransportListener(this._on_close);

  /// Callback recording listener disposal.
  final void Function() _on_close;

  /// Controlled connection stream without native resources.
  final StreamController<TransportConnection> _controller =
      StreamController<TransportConnection>.broadcast();

  /// Retained result of listener disposal.
  Future<void>? _closing;

  /// Exposes the controlled test connection stream.
  @override
  Stream<TransportConnection> get connections => _controller.stream;

  /// Disposes of the controlled listener exactly once.
  @override
  Future<void> close() => _closing ??= _dispose();

  /// Releases the test stream and records successful disposal.
  Future<void> _dispose() async {
    await _controller.close();
    _on_close();
  }
}
