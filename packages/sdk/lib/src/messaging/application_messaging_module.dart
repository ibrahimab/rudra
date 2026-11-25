import 'package:rudra_communication/rudra_communication.dart';

/// Contributes feature-owned application messaging capabilities.
///
/// Each module registers the message codecs required by its
/// application feature. The same contributions can be consumed
/// by host and client communication configurations.
///
/// Registration describes message representations without
/// executing application operations or acquiring resources.
///
/// Example:
/// ```dart
/// final class ExampleMessagingModule
///     implements ApplicationMessagingModule {
///   const ExampleMessagingModule();
///
///   @override
///   String get module_id => 'example.messaging';
///
///   @override
///   void register_codecs(MessageCodecRegistry registry) {
///     registry
///       ..register_request<ExampleResponse, ExampleRequest>(
///         const ExampleRequestCodec(),
///       )
///       ..register_response<ExampleResponse>(
///         const ExampleResponseCodec(),
///       );
///   }
/// }
/// ```
abstract interface class ApplicationMessagingModule {
  /// Stable identifier of the contributing messaging module.
  ///
  /// Identifiers must be nonblank and unique within an
  /// application messaging configuration.
  String get module_id;

  /// Contributes feature-owned codecs to [registry].
  ///
  /// The supplied registry remains mutable throughout contribution
  /// collection. The application composition boundary owns its
  /// configuration lifecycle and final validation.
  ///
  /// Implementations must neither freeze nor retain the registry.
  ///
  /// Registration failures propagate to the composition boundary.
  void register_codecs(MessageCodecRegistry registry);
}
