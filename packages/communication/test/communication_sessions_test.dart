import 'dart:async';
import 'dart:typed_data';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:test/test.dart';

import 'support/registered_test_communication.dart';

/// Verifies public communication configuration, typed connectivity
/// and complete application-resource ownership lifecycles.
void main() {
  const owner = 'test-owner';

  /// Starts a listening communication lifecycle.
  ///
  /// [transport] supplies the substituted native connectivity.
  /// [handler] optionally executes incoming application requests.
  ///
  /// Returns the executing communication instance, shutdown
  /// notification and retained execution result.
  Future<
    ({
      Communication communication,
      Completer<void> shutdown,
      Future<void> running,
    })
  >
  start_server(
    _LoopbackTransport transport, {
    RequestHandler<_EchoResponse, _EchoRequest>? handler,
  }) async {
    final shutdown = Completer<void>();
    final ready = Completer<void>();

    final communication = registered_test_communication(
      [transport],
      codecs: _create_codecs(),
      handlers: _create_handlers(handler),
    );

    final running = communication.run(
      shutdown: shutdown.future,
      on_startup: () async {
        ready.complete();
      },
    );

    running.ignore();

    addTearDown(() async {
      if (!shutdown.isCompleted) {
        shutdown.complete();
      }

      await running;
    });

    await ready.future;

    return (communication: communication, shutdown: shutdown, running: running);
  }

  /// Opens an object-level client through the public facade.
  ///
  /// [transport] supplies substituted endpoint establishment.
  /// [handler] optionally handles incoming application requests.
  ///
  /// Returns the owning communication instance and its session.
  Future<({Communication communication, MessageSession session})> start_client(
    _LoopbackTransport transport, {
    RequestHandler<_EchoResponse, _EchoRequest>? handler,
  }) async {
    final communication = registered_test_communication(
      [transport],
      codecs: _create_codecs(),
      handlers: _create_handlers(handler),
    );

    final session = await communication.connect(
      ConnectionParams(transport: transport),
    );

    addTearDown(() async {
      try {
        await session.close();
      } finally {
        await communication.done;
      }
    });

    return (communication: communication, session: session);
  }

  group('communication configuration', () {
    test('invalid session limits prevent listener acquisition', () async {
      final transport = _LoopbackTransport(os_user_id: owner);

      final communication = registered_test_communication([
        transport,
      ], options: const MessageSessionOptions(maximum_incoming: 0));

      final lifecycle_failed = expectLater(
        communication.done,
        throwsArgumentError,
      );

      await expectLater(
        communication.run(shutdown: Future<void>.value()),
        throwsArgumentError,
      );

      await lifecycle_failed;

      expect(transport.listen_count, 0);
      expect(communication.resources_released, isTrue);
    });

    test('invalid session limits prevent outbound acquisition', () async {
      final transport = _LoopbackTransport(os_user_id: owner);

      final communication = registered_test_communication([
        transport,
      ], options: const MessageSessionOptions(maximum_pending: 0));

      await expectLater(
        communication.connect(ConnectionParams(transport: transport)),
        throwsArgumentError,
      );

      expect(transport.connect_count, 0);
      expect(communication.resources_released, isTrue);
    });

    test('invalid codec configuration prevents listener acquisition', () async {
      final transport = _LoopbackTransport(os_user_id: owner);
      final codecs = MessageCodecRegistry();

      // Deliberately omit the response codec required by this
      // application request registration.
      codecs.register_request<_EchoResponse, _EchoRequest>(
        const _EchoRequestCodec(),
      );

      final communication = registered_test_communication([
        transport,
      ], codecs: codecs);

      await expectLater(
        communication.run(shutdown: Future<void>.value()),
        throwsStateError,
      );

      expect(transport.listen_count, 0);
      expect(communication.resources_released, isTrue);
    });

    test(
      'freezes application registration before native acquisition',
      () async {
        final codecs = _create_codecs();
        final handlers = _create_handlers(null);

        final transport = _LoopbackTransport(
          os_user_id: owner,
          on_listen: () {
            expect(codecs.is_frozen, isTrue);
            expect(handlers.is_frozen, isTrue);
          },
        );

        final communication = registered_test_communication(
          [transport],
          codecs: codecs,
          handlers: handlers,
        );

        expect(codecs.is_frozen, isFalse);
        expect(handlers.is_frozen, isFalse);

        await communication.run(shutdown: Future<void>.value());

        await communication.done;

        expect(communication.resources_released, isTrue);
      },
    );

    test('rejects an incompatible frozen handler registry', () async {
      final transport = _LoopbackTransport(os_user_id: owner);

      final original_codecs = _create_codecs()..freeze();

      final handlers = RequestHandlerRegistry()
        ..freeze(codecs: original_codecs);

      final communication = registered_test_communication(
        [transport],
        codecs: _create_codecs(),
        handlers: handlers,
      );

      await expectLater(
        communication.connect(ConnectionParams(transport: transport)),
        throwsStateError,
      );

      expect(transport.connect_count, 0);
      expect(communication.resources_released, isTrue);
    });
  });

  group('public typed connectivity', () {
    test('exchanges typed requests through the public facade', () async {
      final transport = _LoopbackTransport(os_user_id: owner);

      final server = await start_server(
        transport,
        handler: (request, session) {
          expect(session.os_user_id, owner);

          return _EchoResponse(request.value);
        },
      );

      final client = await start_client(transport);

      expect(client.session.os_user_id, owner);
      expect(client.communication.resources_released, isFalse);
      expect(server.communication.resources_released, isFalse);

      final response = await client.session.request(
        const _EchoRequest('Hello'),
      );

      expect(response.value, 'Hello');

      await client.session.close();
      await client.communication.done;

      expect(client.communication.resources_released, isTrue);
      expect(server.communication.resources_released, isFalse);

      server.shutdown.complete();

      await server.running;
      await server.communication.done;

      expect(server.communication.resources_released, isTrue);
    });

    test('maintains independent concurrent client sessions', () async {
      final transport = _LoopbackTransport(os_user_id: owner);

      await start_server(
        transport,
        handler: (request, session) {
          return _EchoResponse(request.value);
        },
      );

      final first = await start_client(transport);
      final second = await start_client(transport);

      final responses = await Future.wait([
        first.session.request(const _EchoRequest('first')),
        second.session.request(const _EchoRequest('second')),
      ]);

      expect(responses.map((response) => response.value), ['first', 'second']);

      await first.session.close();
      await first.communication.done;

      final response = await second.session.request(
        const _EchoRequest('still connected'),
      );

      expect(response.value, 'still connected');
      expect(first.communication.resources_released, isTrue);
      expect(second.communication.resources_released, isFalse);
    });

    test('isolates malformed client communication', () async {
      final transport = _LoopbackTransport(os_user_id: owner);

      final server = await start_server(
        transport,
        handler: (request, session) {
          return _EchoResponse(request.value);
        },
      );

      final first = await start_client(transport);

      final raw_connection = transport.last_client!;

      final second = await start_client(transport);

      // Inject a malformed frame through the controlled test
      // transport rather than the public messaging API.
      await raw_connection.send(Uint8List(4));

      await first.communication.done;

      expect(first.communication.resources_released, isTrue);
      expect(server.communication.resources_released, isFalse);

      final response = await second.session.request(
        const _EchoRequest('healthy client'),
      );

      expect(response.value, 'healthy client');
    });

    test('a client cannot claim a second execution lifecycle', () async {
      final transport = _LoopbackTransport(os_user_id: owner);

      await start_server(transport);

      final client = await start_client(transport);

      await expectLater(client.communication.connect(), throwsStateError);

      await expectLater(
        client.communication.run(shutdown: Future<void>.value()),
        throwsStateError,
      );

      expect(transport.connect_count, 1);
      expect(transport.listen_count, 1);
      expect(client.communication.resources_released, isFalse);
    });

    test('a listening instance cannot claim a client lifecycle', () async {
      final transport = _LoopbackTransport(os_user_id: owner);
      final server = await start_server(transport);

      await expectLater(server.communication.connect(), throwsStateError);

      expect(transport.connect_count, 0);
      expect(server.communication.resources_released, isFalse);
    });
  });

  group('complete owning lifecycle', () {
    test('host shutdown awaits outstanding application handlers', () async {
      final transport = _LoopbackTransport(os_user_id: owner);

      final entered = Completer<void>();
      final release = Completer<_EchoResponse>();

      final server = await start_server(
        transport,
        handler: (request, session) {
          entered.complete();

          return release.future;
        },
      );

      final client = await start_client(transport);

      final request_failed = expectLater(
        client.session.request(const _EchoRequest('Hello')),
        throwsA(_closed_failure()),
      );

      try {
        await entered.future;

        var server_finished = false;

        final completion = server.running.then<void>((_) {
          server_finished = true;
        });

        server.shutdown.complete();

        // The client observes communication termination while
        // the server's application operation remains outstanding.
        await client.session.done;
        await request_failed;

        expect(server_finished, isFalse);
        expect(server.communication.resources_released, isFalse);

        release.complete(const _EchoResponse('completed'));

        await completion;
        await server.communication.done;

        expect(server_finished, isTrue);
        expect(server.communication.resources_released, isTrue);
      } finally {
        if (!release.isCompleted) {
          release.complete(const _EchoResponse('cleanup'));
        }
      }
    });

    test('client ownership outlives communication disposal while '
        'an application handler remains active', () async {
      final transport = _LoopbackTransport(os_user_id: owner);

      final entered = Completer<void>();
      final release = Completer<_EchoResponse>();

      await start_server(
        transport,
        handler: (request, session) async {
          return await session.request(_EchoRequest(request.value));
        },
      );

      final client = await start_client(
        transport,
        handler: (request, session) {
          entered.complete();

          return release.future;
        },
      );

      final request_failed = expectLater(
        client.session.request(const _EchoRequest('nested request')),
        throwsA(_closed_failure()),
      );

      try {
        await entered.future;

        var owner_finished = false;

        final completion = client.communication.done.then<void>((_) {
          owner_finished = true;
        });

        await client.session.close();
        await client.session.done;
        await request_failed;

        expect(owner_finished, isFalse);
        expect(client.communication.resources_released, isFalse);

        release.complete(const _EchoResponse('completed'));

        await completion;

        expect(owner_finished, isTrue);
        expect(client.communication.resources_released, isTrue);
      } finally {
        if (!release.isCompleted) {
          release.complete(const _EchoResponse('cleanup'));
        }
      }
    });

    test('failed outbound establishment confirms resource release', () async {
      final transport = _LoopbackTransport(os_user_id: owner);

      final communication = registered_test_communication([transport]);

      final lifecycle_failed = expectLater(
        communication.done,
        throwsStateError,
      );

      // No listening endpoint has been established.
      await expectLater(
        communication.connect(ConnectionParams(transport: transport)),
        throwsStateError,
      );

      await lifecycle_failed;

      expect(transport.connect_count, 1);
      expect(communication.resources_released, isTrue);
    });

    test('failed session opening disposes the acquired connection', () async {
      final failure = StateError(
        'Controlled incoming stream initialization failure.',
      );

      final transport = _LoopbackTransport(
        os_user_id: owner,
        incoming_failure: failure,
      );

      await start_server(transport);

      final communication = registered_test_communication([transport]);

      final lifecycle_failed = expectLater(
        communication.done,
        throwsA(same(failure)),
      );

      await expectLater(
        communication.connect(ConnectionParams(transport: transport)),
        throwsA(same(failure)),
      );

      await lifecycle_failed;

      expect(transport.last_client!.close_calls, 1);
      expect(communication.resources_released, isTrue);
    });

    test('failed client disposal remains independently observable', () async {
      final failure = StateError(
        'Controlled client resource disposal failure.',
      );

      final transport = _LoopbackTransport(
        os_user_id: owner,
        close_failure: failure,
      );

      await start_server(transport);

      final communication = registered_test_communication([transport]);

      final session = await communication.connect(
        ConnectionParams(transport: transport),
      );

      final lifecycle_failed = expectLater(
        communication.done,
        throwsA(same(failure)),
      );

      await expectLater(session.close(), throwsA(same(failure)));

      await lifecycle_failed;

      expect(transport.last_client!.close_calls, 1);
      expect(communication.resources_released, isFalse);
    });
  });
}

/// Returns a matcher for the session termination failure.
Matcher _closed_failure() {
  return isA<MessageSessionException>().having(
    (error) => error.code,
    'code',
    MessageSessionErrorCode.session_closed,
  );
}

/// Creates mutable codec registration for synthetic messages.
///
/// Returns configuration that will be frozen by communication.
MessageCodecRegistry _create_codecs() {
  final codecs = MessageCodecRegistry();

  codecs.register_request<_EchoResponse, _EchoRequest>(
    const _EchoRequestCodec(),
  );

  codecs.register_response<_EchoResponse>(const _EchoResponseCodec());

  return codecs;
}

/// Creates mutable application handler configuration.
///
/// [handler] optionally supplies the synthetic request handler.
/// Returns an empty registry when no handler is supplied.
RequestHandlerRegistry _create_handlers(
  RequestHandler<_EchoResponse, _EchoRequest>? handler,
) {
  final handlers = RequestHandlerRegistry();

  if (handler != null) {
    handlers.register<_EchoResponse, _EchoRequest>(handler);
  }

  return handlers;
}

/// Synthetic application request carrying a string.
///
/// Example:
/// ```dart
/// const request = _EchoRequest('Hello');
/// ```
final class _EchoRequest implements Request<_EchoResponse> {
  /// Creates a request containing [value].
  const _EchoRequest(this.value);

  /// Synthetic application request value.
  final String value;
}

/// Synthetic application response carrying a string.
///
/// Example:
/// ```dart
/// const response = _EchoResponse('Hello');
/// ```
final class _EchoResponse implements Response {
  /// Creates a response containing [value].
  const _EchoResponse(this.value);

  /// Synthetic application response value.
  final String value;
}

/// Converts synthetic echo requests to and from string payloads.
final class _EchoRequestCodec implements MessageCodec<_EchoRequest> {
  /// Creates the request codec.
  const _EchoRequestCodec();

  /// Stable request wire identifier.
  @override
  String get type_id => 'example.echo.request.v1';

  /// Returns the string carried by [message].
  @override
  Object? encode(_EchoRequest message) => message.value;

  /// Reconstructs a request from [payload].
  ///
  /// Throws [FormatException] for a non-string payload.
  @override
  _EchoRequest decode(Object? payload) {
    if (payload is! String) {
      throw const FormatException('Invalid echo request payload.');
    }

    return _EchoRequest(payload);
  }
}

/// Converts synthetic echo responses to and from string payloads.
final class _EchoResponseCodec implements MessageCodec<_EchoResponse> {
  /// Creates the response codec.
  const _EchoResponseCodec();

  /// Stable response wire identifier.
  @override
  String get type_id => 'example.echo.response.v1';

  /// Returns the string carried by [message].
  @override
  Object? encode(_EchoResponse message) => message.value;

  /// Reconstructs a response from [payload].
  ///
  /// Throws [FormatException] for a non-string payload.
  @override
  _EchoResponse decode(Object? payload) {
    if (payload is! String) {
      throw const FormatException('Invalid echo response payload.');
    }

    return _EchoResponse(payload);
  }
}

/// Supplies configured bidirectional endpoint establishment.
///
/// Connects independent in-memory transport endpoints without
/// substituting any object-level communication components.
final class _LoopbackTransport implements Transport {
  /// Creates a transport with controlled connectivity behavior.
  ///
  /// [os_user_id] supplies the synthetic authenticated peer identity.
  /// [on_listen] observes listener initialization.
  /// [incoming_failure] optionally rejects client stream access.
  /// [close_failure] optionally rejects client disposal confirmation.
  _LoopbackTransport({
    required this.os_user_id,
    this.on_listen,
    this.incoming_failure,
    this.close_failure,
  });

  /// Trusted synthetic identity retained by this transport.
  final String os_user_id;

  /// Optional listener initialization observer.
  final void Function()? on_listen;

  /// Optional client stream initialization failure.
  final Object? incoming_failure;

  /// Optional client disposal failure.
  final Object? close_failure;

  /// Currently established listener.
  _LoopbackListener? _listener;

  /// Number of attempted listener initializations.
  int listen_count = 0;

  /// Number of attempted outbound connections.
  int connect_count = 0;

  /// Most recently acquired client transport.
  _LoopbackConnection? last_client;

  /// Establishes the configured controlled listening endpoint.
  ///
  /// Returns an independently owned listener.
  @override
  Future<TransportListener> listen() async {
    listen_count++;

    on_listen?.call();

    final listener = _LoopbackListener();

    _listener = listener;

    return listener;
  }

  /// Establishes an independent controlled client connection.
  ///
  /// Returns the client endpoint after delivering its counterpart
  /// to the established listener.
  ///
  /// Throws [StateError] when no active listener exists.
  @override
  Future<TransportConnection> connect() async {
    connect_count++;

    final listener = _listener;

    if (listener == null || listener.is_closed) {
      throw StateError('No active test listener.');
    }

    final client = _LoopbackConnection(
      os_user_id: os_user_id,
      incoming_failure: incoming_failure,
      close_failure: close_failure,
    );

    final server = _LoopbackConnection(os_user_id: os_user_id);

    client.peer = server;
    server.peer = client;

    last_client = client;

    listener.accept(server);

    return client;
  }
}

/// Retains controlled accepted connections for lifecycle verification.
final class _LoopbackListener implements TransportListener {
  /// Creates an inactive controlled listener.
  _LoopbackListener();

  /// Controlled authenticated connection stream.
  final StreamController<TransportConnection> _accepted =
      StreamController<TransportConnection>();

  /// Server connections retained during the fixture lifecycle.
  final Set<_LoopbackConnection> _connections = {};

  /// Retained listener disposal result.
  Future<void>? _closing;

  /// Whether listener disposal has begun.
  bool is_closed = false;

  /// Supplies accepted authenticated connections.
  @override
  Stream<TransportConnection> get connections => _accepted.stream;

  /// Delivers the authenticated server endpoint [connection].
  void accept(_LoopbackConnection connection) {
    if (is_closed) {
      throw StateError('Test listener is closed.');
    }

    _connections.add(connection);
    _accepted.add(connection);
  }

  /// Terminates listening and all retained connections.
  ///
  /// Returns the retained disposal result on repeated calls.
  @override
  Future<void> close() => _closing ??= _dispose();

  /// Releases controlled listener and connection resources.
  Future<void> _dispose() async {
    is_closed = true;

    try {
      await Future.wait<void>(
        _connections.map((connection) => connection.close()),
      );
    } finally {
      _connections.clear();

      // Startup failure may leave this single-subscription
      // stream without a consumer.
      _accepted.close().ignore();
    }
  }
}

/// Represents one independently owned in-memory transport endpoint.
final class _LoopbackConnection implements TransportConnection {
  /// Creates a controlled connection with authenticated [os_user_id].
  ///
  /// [incoming_failure] optionally rejects stream initialization.
  /// [close_failure] optionally rejects disposal confirmation.
  _LoopbackConnection({
    required this.os_user_id,
    this.incoming_failure,
    this.close_failure,
  });

  /// Synthetic trusted peer identity.
  @override
  final String os_user_id;

  /// Optional incoming stream initialization failure.
  final Object? incoming_failure;

  /// Optional resource disposal failure.
  final Object? close_failure;

  /// Independently owned endpoint receiving transmitted bytes.
  late final _LoopbackConnection peer;

  /// Incoming single-subscription byte stream.
  final StreamController<Uint8List> _input = StreamController<Uint8List>();

  /// Whether connection termination has begun.
  bool _closed = false;

  /// Retained connection disposal result.
  Future<void>? _closing;

  /// Number of actual connection disposal operations.
  int close_calls = 0;

  /// Supplies the controlled incoming byte stream.
  ///
  /// Throws the configured initialization failure when present.
  @override
  Stream<Uint8List> get incoming {
    final failure = incoming_failure;

    if (failure != null) {
      throw failure;
    }

    return _input.stream;
  }

  /// Delivers an independent copy of [bytes] to the peer.
  ///
  /// Throws [StateError] after either endpoint has disconnected.
  @override
  Future<void> send(Uint8List bytes) async {
    if (_closed || peer._input.isClosed) {
      throw StateError('Test connection is closed.');
    }

    peer._input.add(Uint8List.fromList(bytes));
  }

  /// Terminates communication in both directions.
  ///
  /// Returns the retained disposal result on repeated calls.
  @override
  Future<void> close() => _closing ??= _dispose();

  /// Releases controlled communication resources.
  ///
  /// Throws the configured disposal failure when present.
  Future<void> _dispose() async {
    close_calls++;

    _closed = true;

    _finish_input();
    peer._finish_input();

    final failure = close_failure;

    if (failure != null) {
      throw failure;
    }
  }

  /// Signals termination of incoming byte delivery.
  void _finish_input() {
    if (!_input.isClosed) {
      _input.close().ignore();
    }
  }
}
