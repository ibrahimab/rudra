import 'dart:async';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:test/test.dart';

/// Verifies communication construction, substitution and resource ownership.
void main() {
  /// Executes one communication lifecycle without incoming connections.
  ///
  /// [communication] supplies the subsystem under test.
  /// [on_startup] optionally exercises application initialization.
  ///
  /// Returns after shutdown and disposal, or propagates execution failures.
  Future<void> run_once(
    Communication communication, {
    Future<void> Function()? on_startup,
  }) =>
      communication.run(shutdown: Future<void>.value(), on_startup: on_startup);

  test('construction acquires no communication resources', () {
    final transport = _TestTransport();

    final communication = Communication(listening_transports: [transport]);

    expect(transport.listen_count, 0);
    expect(communication.resources_released, isTrue);
  });

  test('configured transport initializes only during execution', () async {
    final transport = _TestTransport();

    final communication = Communication(listening_transports: [transport]);

    expect(transport.listen_count, 0);
    expect(communication.resources_released, isTrue);

    await run_once(
      communication,
      on_startup: () async {
        expect(transport.listen_count, 1);
        expect(communication.resources_released, isFalse);
      },
    );

    expect(transport.listener.close_calls, 1);
    expect(communication.resources_released, isTrue);
  });

  test('failed initialization retains no communication resources', () async {
    final transport = _TestTransport(fail_binding: true);

    final communication = Communication(listening_transports: [transport]);

    await expectLater(
      run_once(
        communication,
        on_startup: () async {
          fail('Failed initialization must not report readiness.');
        },
      ),
      throwsStateError,
    );

    expect(transport.listen_count, 1);
    expect(transport.listener.close_calls, 0);
    expect(communication.resources_released, isTrue);
  });

  test('failed application startup releases the acquired listener', () async {
    final transport = _TestTransport();

    final communication = Communication(listening_transports: [transport]);

    final failure = StateError('Controlled application startup failure.');

    await expectLater(
      run_once(
        communication,
        on_startup: () async {
          throw failure;
        },
      ),
      throwsA(same(failure)),
    );

    expect(transport.listener.close_calls, 1);
    expect(communication.resources_released, isTrue);
  });

  test('failed listener disposal remains unconfirmed', () async {
    final transport = _TestTransport(fail_disposal: true);

    final communication = Communication(listening_transports: [transport]);

    await expectLater(run_once(communication), throwsStateError);

    expect(transport.listener.close_calls, 1);
    expect(communication.resources_released, isFalse);
  });

  test('activates each enabled listener before announcing readiness', () async {
    final first = _TestTransport();
    final second = _TestTransport();
    final communication = Communication(listening_transports: [first, second]);

    await run_once(
      communication,
      on_startup: () async {
        expect(first.listen_count, 1);
        expect(second.listen_count, 1);
      },
    );
    expect(first.listener.close_calls, 1);
    expect(second.listener.close_calls, 1);
    expect(communication.resources_released, isTrue);
  });

  for (final fail_disposal in [false, true]) {
    test(
      'partial activation rolls back listeners (disposal failure: $fail_disposal)',
      () async {
        final first = _TestTransport(fail_disposal: fail_disposal);
        final second = _TestTransport(fail_binding: true);
        final communication = Communication(
          listening_transports: [first, second],
        );

        await expectLater(
          run_once(
            communication,
            on_startup: () async => fail('Host reported readiness.'),
          ),
          fail_disposal
              ? throwsA(isA<TransportDisposalException>())
              : throwsStateError,
        );
        expect(first.listener.close_calls, 1);
        expect(second.listener.close_calls, 0);
        expect(communication.resources_released, !fail_disposal);
      },
    );
  }

  test('duplicate enabled endpoints fail before activation', () async {
    final transport = _TestTransport();
    final communication = Communication(
      listening_transports: [transport, transport],
    );

    await expectLater(run_once(communication), throwsArgumentError);
    expect(transport.listen_count, 0);
    expect(communication.resources_released, isTrue);
  });

  test('communication cannot execute twice', () async {
    final transport = _TestTransport();

    final communication = Communication(listening_transports: [transport]);

    await run_once(communication);

    await expectLater(run_once(communication), throwsStateError);

    expect(transport.listen_count, 1);
    expect(transport.listener.close_calls, 1);
    expect(communication.resources_released, isTrue);
  });
}

/// Provides a controlled transport for communication lifecycle tests.
///
/// Supports controlled binding and listener disposal failures
/// without acquiring native resources.
///
/// Example:
/// ```dart
/// final transport = _TestTransport();
/// final communication = Communication(listening_transports: [transport]);
/// ```
final class _TestTransport implements Transport {
  /// Creates a transport with controlled failure behavior.
  ///
  /// [fail_binding] requests an initialization failure.
  /// [fail_disposal] requests a listener disposal failure.
  _TestTransport({this.fail_binding = false, bool fail_disposal = false})
    : listener = _TestListener(fail_disposal: fail_disposal);

  /// Whether transport initialization should fail.
  final bool fail_binding;

  /// Controlled listener returned after successful initialization.
  final _TestListener listener;

  /// Number of attempted transport initializations.
  int listen_count = 0;

  /// Establishes the controlled listening endpoint.
  ///
  /// Returns the controlled listener or throws [StateError]
  /// when initialization failure has been configured.
  @override
  Future<TransportListener> listen() async {
    listen_count++;

    if (fail_binding) {
      throw StateError('Controlled transport initialization failure.');
    }

    return listener;
  }

  /// Rejects outbound connection establishment for this fixture.
  ///
  /// Throws [UnsupportedError] because this fixture exclusively
  /// exercises listener lifecycle ownership.
  @override
  Future<TransportConnection> connect() async {
    throw UnsupportedError('Outbound connectivity is outside this fixture.');
  }
}

/// Supplies an idle listener with observable disposal behavior.
///
/// Example:
/// ```dart
/// final listener = _TestListener(fail_disposal: false);
///
/// await listener.close();
/// assert(listener.close_calls == 1);
/// ```
final class _TestListener implements TransportListener {
  /// Creates a listener with the requested [fail_disposal] behavior.
  _TestListener({required this.fail_disposal});

  /// Whether listener disposal should report failure.
  final bool fail_disposal;

  /// Controlled stream representing accepted connections.
  final StreamController<TransportConnection> _controller =
      StreamController<TransportConnection>();

  /// Retained result of the first disposal operation.
  Future<void>? _closing;

  /// Number of requests to dispose of this listener.
  int close_calls = 0;

  /// Supplies the controlled single-subscription connection stream.
  @override
  Stream<TransportConnection> get connections => _controller.stream;

  /// Records disposal and returns its retained result.
  @override
  Future<void> close() {
    close_calls++;

    return _closing ??= _dispose();
  }

  /// Closes the controlled connection stream.
  ///
  /// Throws [StateError] when unsuccessful disposal is configured.
  Future<void> _dispose() async {
    final has_listener = _controller.hasListener;
    final completion = _controller.close();

    // Startup can fail before the stream receives a subscriber.
    // In that situation, no stream consumer needs to terminate.
    if (has_listener) {
      await completion;
    } else {
      unawaited(completion);
    }

    if (fail_disposal) {
      throw StateError('Controlled listener disposal failure.');
    }
  }
}
