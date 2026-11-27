import 'contracts/transport.dart';
import 'macos/unix/macos_unix_transport.dart';
import 'transport_configuration.dart';
import 'transport_registration.dart';

/// Catalog of available transports and the native default for each platform.
///
/// Communication enables the native default when the caller supplies no
/// overrides. The registry itself never binds endpoints or connects to a host.
///
/// ### Example
///
/// ```dart
/// final registry = TransportRegistry([MacOsUnixTransport.registration]);
/// final transport = registry.create_default('macos');
/// ```
final class TransportRegistry {
  /// Validates and retains [registrations] without invoking their factories.
  ///
  /// Throws [ArgumentError] for blank or duplicate implementation IDs or
  /// if more than one transport is registered as the default for a platform.
  TransportRegistry(Iterable<TransportRegistration> registrations) {
    for (final entry in registrations) {
      final platform = entry.default_platform;
      if (entry.id.trim().isEmpty || _available.containsKey(entry.id)) {
        throw ArgumentError.value(
          entry.id,
          'id',
          'Invalid transport registration.',
        );
      }
      if (platform != null) {
        if (platform.trim().isEmpty || _default_ids.containsKey(platform)) {
          throw ArgumentError.value(
            platform,
            'default_platform',
            'Invalid platform default.',
          );
        }
        _default_ids[platform] = entry.id;
      }
      _available[entry.id] = entry.create;
    }
  }

  /// Registers macOS Unix-domain IPC as the first native implementation.
  static final standard = TransportRegistry([MacOsUnixTransport.registration]);

  /// Factories indexed by transport implementation ID.
  final _available = <String, Transport Function(Map<String, String>)>{};

  /// Native local defaults indexed by operating system.
  final _default_ids = <String, String>{};

  /// Constructs the inactive native default for [platform].
  ///
  /// Throws [UnsupportedError] when no default is registered for the platform.
  Transport create_default(String platform) {
    final id = _default_ids[platform];
    if (id == null) {
      throw UnsupportedError('No Rudra transport is available for $platform.');
    }
    return _available[id]!(const {});
  }

  /// Constructs the inactive transport selected by [endpoint].
  ///
  /// Throws [ArgumentError] for an unknown registration. Option validation
  /// errors from the registered implementation propagate to the caller.
  Transport create(TransportEndpoint endpoint) {
    final factory = _available[endpoint.transport_id];
    if (factory == null) {
      throw ArgumentError.value(endpoint.transport_id, 'transport_id');
    }
    return factory(endpoint.options);
  }
}
