/// Represents an application object exchanged through communication.
///
/// Application messages describe application data and behavior.
/// Their wire representation, correlation and delivery are maintained
/// independently by the communication infrastructure.
///
/// Example:
/// ```dart
/// final class EchoResponse implements Response {
///   const EchoResponse(this.value);
///
///   final String value;
/// }
/// ```
abstract interface class Message {}

/// Represents the application result of a communication request.
///
/// Response objects may describe successful application operations
/// or expected application rejections.
///
/// Example:
/// ```dart
/// final class EchoResponse implements Response {
///   const EchoResponse(this.value);
///
///   final String value;
/// }
/// ```
abstract interface class Response implements Message {}

/// Represents a request expecting a response of type [R].
///
/// The response type establishes the typed relationship between
/// an application request and its corresponding result.
///
/// Communication uses this relationship to provide typed request
/// execution without embedding protocol metadata in application objects.
///
/// Example:
/// ```dart
/// final class EchoRequest implements Request<EchoResponse> {
///   const EchoRequest(this.value);
///
///   final String value;
/// }
/// ```
abstract interface class Request<R extends Response> implements Message {}
