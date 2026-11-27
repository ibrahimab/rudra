/// Configures one listener provided by a registered transport implementation.
///
/// Example:
/// ```dart
/// final endpoint = MacOsUnixTransport.endpoint(socket_path: socket_path);
/// print(endpoint.transport_id);
/// ```
final class TransportEndpoint {
  /// Captures [transport_id] and a snapshot of its implementation [options].
  ///
  /// Throws [ArgumentError] for a blank registration ID. The registered
  /// implementation validates its own options during resolution.
  TransportEndpoint({
    required this.transport_id,
    Map<String, String> options = const {},
  }) : options = Map.unmodifiable(options) {
    if (transport_id.trim().isEmpty) {
      throw ArgumentError.value(transport_id, 'transport_id');
    }
  }

  /// Key of the registered implementation that constructs this endpoint.
  final String transport_id;

  /// Transport-specific, immutable endpoint settings.
  final Map<String, String> options;
}

/// Selects listening endpoints for one host lifecycle.
///
/// Example:
/// ```dart
/// final configuration = TransportConfiguration.enabled([
///   MacOsUnixTransport.endpoint(),
/// ]);
/// ```
final class TransportConfiguration {
  /// Enables only the native local default for the current platform.
  const TransportConfiguration.native() : endpoints = null;

  /// Enables the supplied [endpoints] in order.
  ///
  /// Throws [ArgumentError] for an empty list or repeated endpoint
  /// configuration. No transport is constructed or activated here.
  TransportConfiguration.enabled(Iterable<TransportEndpoint> endpoints)
    : endpoints = List.unmodifiable(endpoints) {
    final enabled = this.endpoints!;
    if (enabled.isEmpty) {
      throw ArgumentError('Enable at least one listener.');
    }
    for (var i = 0; i < enabled.length; i++) {
      final endpoint = enabled[i];
      if (enabled
          .take(i)
          .any(
            (previous) =>
                previous.transport_id == endpoint.transport_id &&
                previous.options.length == endpoint.options.length &&
                previous.options.entries.every(
                  (option) => endpoint.options[option.key] == option.value,
                ),
          )) {
        throw ArgumentError('Duplicate listener for ${endpoint.transport_id}.');
      }
    }
  }

  /// The explicit listeners in activation order, or null for the native default.
  final List<TransportEndpoint>? endpoints;
}
