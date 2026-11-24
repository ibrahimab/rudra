import 'dart:async';

import 'package:rudra_sdk/rudra_sdk.dart';

/// Provides an isolated transport for host composition tests.
///
/// Records listener creation without binding native endpoints
/// or accepting real operating-system connections.
///
/// Example:
/// ```dart
/// final transport = TestHostTransport();
///
/// final listener = await transport.listen(
///   scope_directory: '/fixture',
///   os_user_id: 'test-owner',
/// );
///
/// await listener.close();
/// ```
final class TestHostTransport implements HostTransport {
  /// Creates an initially inactive transport fixture.
  TestHostTransport();

  /// Number of successfully created test listeners.
  int listen_count = 0;

  /// Number of successfully disposed test listeners.
  int close_count = 0;

  /// Creates a controlled listener for the supplied scope.
  ///
  /// [scope_directory] and [os_user_id] represent the trusted
  /// configuration supplied by host composition.
  ///
  /// Returns an idle listener with no incoming connections.
  @override
  Future<HostListener> listen({
    required String scope_directory,
    required String os_user_id,
  }) async {
    listen_count++;

    return _TestHostListener(() {
      close_count++;
    });
  }
}

/// Represents an idle listener owned by a composition test.
///
/// Example:
/// ```dart
/// final listener = _TestHostListener(() {});
/// await listener.close();
/// ```
final class _TestHostListener implements HostListener {
  /// Creates a listener with its disposal callback.
  _TestHostListener(this._on_close);

  /// Callback recording listener disposal.
  final void Function() _on_close;

  /// Controlled connection stream without native resources.
  final StreamController<HostConnection> _controller =
      StreamController<HostConnection>.broadcast();

  /// Retained result of listener disposal.
  Future<void>? _closing;

  /// Exposes the controlled test connection stream.
  @override
  Stream<HostConnection> get connections => _controller.stream;

  /// Disposes of the controlled listener exactly once.
  @override
  Future<void> close() => _closing ??= _dispose();

  /// Releases the test stream and records successful disposal.
  Future<void> _dispose() async {
    await _controller.close();
    _on_close();
  }
}
