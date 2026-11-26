import 'dart:io';

import 'package:rudra_communication/rudra_communication.dart';

import 'echo_messages.dart';

/// Executes native communication from an independent process.
///
/// [arguments] contains the canonical communication scope,
/// trusted peer identity, execution scenario and client label.
///
/// The exchange scenario verifies nested requests, sanitized
/// remote failures and continued communication.
///
/// The hold scenario waits for termination of an outstanding
/// request whose remote handler remains active.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 4) {
    throw ArgumentError('Invalid native client arguments.');
  }

  final scope = arguments[0];
  final owner = arguments[1];
  final scenario = arguments[2];
  final label = arguments[3];

  final handlers = RequestHandlerRegistry()
    ..register<EchoResponse, EchoRequest>((request, session) {
      _require(session.os_user_id == owner, 'Invalid remote owner.');

      return EchoResponse('client:${request.value}');
    });

  final communication = Communication(
    codecs: create_echo_codecs(),
    handlers: handlers,
    options: const MessageSessionOptions(
      request_timeout: Duration(seconds: 45),
    ),
  );

  final session = await communication.connect(
    ConnectionParams(
      transport: MacOsUnixTransport(socket_path: '$scope/rudra.sock'),
    ),
  );

  try {
    _require(session.os_user_id == owner, 'Invalid session owner.');

    switch (scenario) {
      case 'exchange':
        await _exchange(session, label);
        break;

      case 'hold':
        await _hold(session);
        break;

      default:
        throw ArgumentError.value(scenario, 'scenario');
    }
  } finally {
    try {
      await session.close();
    } finally {
      await communication.done;
    }
  }

  _require(
    communication.resources_released,
    'Client resource disposal was not confirmed.',
  );

  stdout.writeln('RELEASED');
}

/// Verifies native typed communication through [session].
///
/// [label] distinguishes this client's application messages
/// from requests submitted by independently executing clients.
///
/// Returns after successful nested messaging and failure recovery.
Future<void> _exchange(MessageSession session, String label) async {
  final response = await session.request(EchoRequest(label));

  _require(
    response.value == 'host:client:$label',
    'Unexpected nested response.',
  );

  try {
    await session.request(const EchoRequest('fail'));

    throw StateError('Remote handler failure was expected.');
  } on MessageSessionException catch (error) {
    _require(
      error.code == MessageSessionErrorCode.handler_failed,
      'Unexpected remote failure classification.',
    );

    _require(
      error.toString() == 'MessageSessionException(handler_failed)',
      'Unexpected remote diagnostic content.',
    );
  }

  // Remote application failure must not invalidate the session.
  final recovered = await session.request(EchoRequest('$label:recovered'));

  _require(
    recovered.value == 'host:client:$label:recovered',
    'Communication did not recover after handler failure.',
  );

  stdout.writeln('EXCHANGED:$label');
}

/// Waits for termination of an outstanding request on [session].
///
/// Returns after the remote endpoint closes communication.
/// Throws [StateError] if the outstanding request unexpectedly
/// succeeds or terminates with an incompatible failure.
Future<void> _hold(MessageSession session) async {
  try {
    await session.request(const EchoRequest('hold'));

    throw StateError('Outstanding request should have failed.');
  } on MessageSessionException catch (error) {
    _require(
      error.code == MessageSessionErrorCode.session_closed,
      'Unexpected outstanding request termination.',
    );
  }

  await session.done;

  stdout.writeln('DISCONNECTED');
}

/// Enforces a fixture [condition] independently of Dart assertions.
///
/// Throws [StateError] containing [message] when the condition
/// is not satisfied.
void _require(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
