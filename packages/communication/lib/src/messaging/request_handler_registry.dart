import 'dart:async';

import '../sessions/message_session.dart';
import 'message.dart';
import 'message_codec_registry.dart';

/// Executes an application request of type [Q] and produces its
/// associated response of type [R].
///
/// [request] contains the decoded application data.
/// [session] identifies the authenticated communication peer and
/// provides access to object-level communication capabilities.
///
/// Handlers may execute synchronous or asynchronous operations.
/// Expected application rejections are represented by application
/// responses. Unexpected execution failures propagate to communication.
///
/// Example:
/// ```dart
/// final RequestHandler<EchoResponse, EchoRequest> handler =
///     (request, session) => EchoResponse(request.value);
/// ```
typedef RequestHandler<R extends Response, Q extends Request<R>> =
    FutureOr<R> Function(Q request, MessageSession session);

/// Maintains application-provided handlers for registered requests.
///
/// Each concrete request type may have one local handler. Handler
/// registrations are validated against frozen message codec
/// configuration before dispatch becomes available.
///
/// The registry owns handler registration and typed invocation.
/// Application execution semantics remain the responsibility of
/// the supplied handler implementations.
///
/// Example:
/// ```dart
/// final handlers = RequestHandlerRegistry();
///
/// handlers.register<EchoResponse, EchoRequest>(
///   (request, session) => EchoResponse(request.value),
/// );
///
/// handlers.freeze(codecs: codecs);
///
/// final response = await handlers.dispatch(
///   const EchoRequest('Hello'),
///   session,
/// );
/// ```
final class RequestHandlerRegistry {
  /// Creates an empty, mutable handler registry.
  ///
  /// Construction does not execute handlers or acquire communication
  /// resources.
  RequestHandlerRegistry();

  /// Handler registrations indexed by concrete request type.
  final Map<Type, _HandlerRegistration> _registrations = {};

  /// Frozen codec configuration associated with this registry.
  ///
  /// Remains null until all handler registrations have been validated.
  MessageCodecRegistry? _codecs;

  /// Whether handler configuration has been validated and frozen.
  bool get is_frozen => _codecs != null;

  /// Registers [handler] for concrete request type [Q].
  ///
  /// [R] identifies the concrete response produced by the handler.
  /// The request-to-response relationship must match the associated
  /// codec configuration when the registry is frozen.
  ///
  /// Registration retains the handler without executing it.
  ///
  /// Throws [StateError] for duplicate request registrations or
  /// when configuration has already been frozen.
  void register<R extends Response, Q extends Request<R>>(
    RequestHandler<R, Q> handler,
  ) {
    if (is_frozen) {
      throw StateError('Request handler registry is frozen.');
    }

    if (_registrations.containsKey(Q)) {
      throw StateError('Request handler is already registered: $Q.');
    }

    // Capture the concrete generic types before storing the
    // handler in the heterogeneous registration index.
    _registrations[Q] = _HandlerRegistration(
      request_type: Q,
      response_type: R,
      invoke: (request, session) async {
        return await handler(request as Q, session);
      },
    );
  }

  /// Validates and freezes this registry against [codecs].
  ///
  /// The codec registry must already be frozen. Every registered
  /// handler must correspond to a registered request and its
  /// configured concrete response type.
  ///
  /// Registered message codecs need not have local handlers.
  ///
  /// Throws [StateError] for mutable codec configuration, missing
  /// request registrations or incompatible response types.
  ///
  /// Failed validation leaves handler configuration mutable.
  /// Repeated calls with the same validated codec registry have
  /// no additional effect.
  /// Rebinding to a different codec registry throws [StateError].
  void freeze({required MessageCodecRegistry codecs}) {
    if (is_frozen) {
      if (!identical(_codecs, codecs)) {
        throw StateError(
          'Request handler registry cannot change codec configuration.',
        );
      }

      return;
    }

    if (!codecs.is_frozen) {
      throw StateError('Message codec registry is not frozen.');
    }

    for (final registration in _registrations.values) {
      final Type expected_response_type;

      try {
        expected_response_type = codecs.response_type_for_request_type(
          registration.request_type,
        );
      } on ArgumentError {
        throw StateError(
          'Missing request codec for ${registration.request_type}.',
        );
      }

      if (registration.response_type != expected_response_type) {
        throw StateError(
          'Incompatible handler response type for '
          '${registration.request_type}.',
        );
      }
    }

    // Retain configuration only after every registration has
    // passed validation.
    _codecs = codecs;
  }

  /// Delivers [request] to its registered application handler.
  ///
  /// [session] identifies the authenticated peer associated with
  /// the incoming request.
  ///
  /// Returns the validated response produced by the handler,
  /// or null when no local handler is registered.
  ///
  /// Throws [StateError] when configuration has not been frozen
  /// or the returned response violates the registered concrete
  /// response contract.
  /// Throws [ArgumentError] for an unregistered request type.
  ///
  /// Application handler failures propagate unchanged. Session
  /// coordination is responsible for converting them into
  /// sanitized remote request failures.
  ///
  /// Dispatch does not impose application execution ordering or
  /// perform transport writes.
  Future<Response?> dispatch(
    Request<Response> request,
    MessageSession session,
  ) async {
    final codecs = _codecs;

    if (codecs == null) {
      throw StateError('Request handler registry is not frozen.');
    }

    final expected_response_type = codecs.response_type_for(request);
    final registration = _registrations[request.runtimeType];

    if (registration == null) {
      return null;
    }

    final response = await registration.invoke(request, session);

    // Validate the concrete response independently of the generic
    // covariance permitted by the application handler signature.
    if (response.runtimeType != expected_response_type ||
        response is Request<Response>) {
      throw StateError('Handler returned an incompatible response type.');
    }

    return response;
  }
}

/// Retains the typed relationship and invocation adapter of one
/// registered application handler.
///
/// The adapter encapsulates the heterogeneous storage boundary,
/// allowing the registry to dispatch concrete application requests
/// without exposing widened handler types to consumers.
final class _HandlerRegistration {
  /// Creates a registration for the supplied application handler.
  ///
  /// [request_type] identifies the concrete accepted request.
  /// [response_type] identifies the concrete produced response.
  /// [invoke] adapts generic dispatch to the typed handler.
  const _HandlerRegistration({
    required this.request_type,
    required this.response_type,
    required this.invoke,
  });

  /// Concrete request type accepted by the handler.
  final Type request_type;

  /// Concrete response type produced by the handler.
  final Type response_type;

  /// Invocation adapter retaining the handler's generic relationship.
  final Future<Response> Function(Request<Response>, MessageSession) invoke;
}
