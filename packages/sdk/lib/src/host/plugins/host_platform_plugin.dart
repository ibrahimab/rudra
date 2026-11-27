/// Contributes optional platform capabilities to trusted host composition.
///
/// Plugins register inactive capability implementations.
/// Operational execution and resource ownership remain with
/// the consumers of those capabilities.
///
/// Example:
/// ```dart
/// final class ExamplePlugin implements HostPlatformPlugin {
///   @override
///   String get id => 'example';
///
///   @override
///   void register(HostPlatformRegistration registration) {
///     registration.add<ExampleCapability>(
///       ExampleImplementation(),
///     );
///   }
/// }
/// ```
abstract interface class HostPlatformPlugin {
  /// Stable identifier uniquely identifying this plugin
  /// within a platform registry.
  String get id;

  /// Contributes capabilities through [registration].
  ///
  /// Implementations must complete registration synchronously
  /// without activating capabilities, acquiring native resources
  /// or performing installation operations.
  ///
  /// Registration failures propagate to trusted composition.
  void register(HostPlatformRegistration registration);
}

/// Restricted contribution interface supplied to platform plugins.
///
/// Each capability is registered against its declared Dart contract
/// type. A contract has at most one provider within a registry.
abstract interface class HostPlatformRegistration {
  /// Registers [capability] against the declared contract [T].
  ///
  /// The implementation must remain inactive during registration.
  /// Consumers explicitly invoke its operational methods.
  ///
  /// Throws [StateError] when the contract already has a provider
  /// or the registration scope has closed.
  void add<T extends Object>(T capability);
}
