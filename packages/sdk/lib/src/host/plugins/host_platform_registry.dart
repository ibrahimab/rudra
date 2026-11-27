import 'host_platform_plugin.dart';

/// Immutable registry of capabilities contributed by platform plugins.
///
/// Trusted composition supplies the plugins explicitly. Each capability
/// is indexed by its declared contract type, independently of its
/// concrete implementation.
///
/// Registration completes before capabilities become available
/// to consumers.
///
/// Example:
/// ```dart
/// final registry = HostPlatformRegistry([ExamplePlugin()]);
/// final capability = registry.require<ExampleCapability>();
/// ```
final class HostPlatformRegistry {
  /// Registers and validates the supplied [plugins].
  ///
  /// Plugins are processed in iteration order. Each plugin receives
  /// an independent, temporary registration scope.
  ///
  /// Throws [ArgumentError] for blank plugin identifiers.
  /// Throws [StateError] for duplicate plugin identifiers or
  /// conflicting capability providers.
  ///
  /// Plugin registration failures propagate to the caller.
  /// Construction performs no capability activation.
  factory HostPlatformRegistry(Iterable<HostPlatformPlugin> plugins) {
    final plugin_ids = <String>{};
    final capabilities = <Type, Object>{};

    for (final plugin in plugins) {
      final id = plugin.id;

      if (id.trim().isEmpty) {
        throw ArgumentError.value(id, 'id');
      }

      if (!plugin_ids.add(id)) {
        throw StateError('Duplicate host platform plugin: $id');
      }

      final registration = _PlatformRegistration(
        plugin_id: id,
        capabilities: capabilities,
      );

      try {
        plugin.register(registration);
      } finally {
        registration.close();
      }
    }

    return HostPlatformRegistry._(Map<Type, Object>.unmodifiable(capabilities));
  }

  /// Retains the completed, immutable capability registrations.
  HostPlatformRegistry._(this._capabilities);

  /// Capability implementations indexed by their declared contract type.
  ///
  /// Each contract has exactly one provider when present.
  final Map<Type, Object> _capabilities;

  /// Returns the capability registered against contract [T].
  ///
  /// Matching uses exact declared types without inheritance-based
  /// fallback or registration-order precedence.
  ///
  /// Returns null when the capability is unavailable.
  T? find<T extends Object>() => _capabilities[T] as T?;

  /// Returns the required capability registered against contract [T].
  ///
  /// Throws [StateError] when no provider has been registered
  /// for the requested contract.
  T require<T extends Object>() {
    final capability = find<T>();

    if (capability == null) {
      throw StateError('Missing host platform capability: $T');
    }

    return capability;
  }
}

/// Temporary contribution scope belonging to one platform plugin.
///
/// The enclosing registry owns the capability collection and closes
/// this scope immediately after synchronous plugin registration.
final class _PlatformRegistration implements HostPlatformRegistration {
  /// Creates a registration scope for [plugin_id].
  ///
  /// [capabilities] contains registrations accumulated during
  /// construction of the enclosing registry.
  _PlatformRegistration({
    required this.plugin_id,
    required Map<Type, Object> capabilities,
  }) : _capabilities = capabilities;

  /// Identifier of the plugin contributing capabilities.
  final String plugin_id;

  /// Borrowed capability collection awaiting registry completion.
  final Map<Type, Object> _capabilities;

  /// Whether this registration scope still accepts contributions.
  bool _is_open = true;

  /// Registers [capability] under its declared contract type [T].
  ///
  /// Throws [StateError] when registration has completed or another
  /// provider already owns the requested contract.
  @override
  void add<T extends Object>(T capability) {
    if (!_is_open) {
      throw StateError('Host platform registration is closed: $plugin_id');
    }

    if (_capabilities.containsKey(T)) {
      throw StateError(
        'Duplicate host platform capability: $T '
        '(plugin: $plugin_id)',
      );
    }

    _capabilities[T] = capability;
  }

  /// Ends the contribution scope and prevents further registrations.
  ///
  /// Repeated closure has no additional effect.
  void close() {
    _is_open = false;
  }
}
