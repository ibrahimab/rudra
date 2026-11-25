import 'package:rudra_communication/rudra_communication.dart';

import 'application_messaging_module.dart';
import 'standard_messaging_modules.dart';

/// Assembles a validated application message codec configuration.
///
/// [modules] supplies the messaging capabilities to register.
/// When omitted, the standard Rudra messaging modules are used.
/// An explicitly supplied collection replaces the standard modules.
///
/// Returns a new, frozen [MessageCodecRegistry] containing the
/// contributed message representations.
///
/// Throws [ArgumentError] for a blank module identifier or invalid
/// codec identifier.
///
/// Throws [StateError] for duplicate module identifiers, conflicting
/// codec registrations, premature registry freezing or incomplete
/// request-to-response configuration.
///
/// Exceptions raised by module contributions propagate to the caller.
/// Failed composition does not publish a partially configured registry.
///
/// Example:
/// ```dart
/// final codecs = create_application_message_codecs();
///
/// final communication = Communication(codecs: codecs);
/// ```
///
/// Example with additional application messaging capabilities:
/// ```dart
/// final codecs = create_application_message_codecs(
///   modules: [
///     ...standard_messaging_modules(),
///     const ExampleMessagingModule(),
///   ],
/// );
/// ```
MessageCodecRegistry create_application_message_codecs({
  Iterable<ApplicationMessagingModule>? modules,
}) {
  final registry = MessageCodecRegistry();
  final module_ids = <String>{};

  for (final module in modules ?? standard_messaging_modules()) {
    final module_id = module.module_id;

    if (module_id.trim().isEmpty) {
      throw ArgumentError.value(
        module_id,
        'module_id',
        'Application messaging module identifier must not be blank.',
      );
    }

    if (!module_ids.add(module_id)) {
      throw StateError('Duplicate application messaging module: $module_id');
    }

    module.register_codecs(registry);

    // Only the composition boundary may finalize configuration.
    // Premature freezing could prevent subsequent contributions.
    if (registry.is_frozen) {
      throw StateError(
        'Application messaging module prematurely froze '
        'the codec registry: $module_id',
      );
    }
  }

  // Validate cross-module message relationships only after every
  // feature has contributed its messaging capabilities.
  registry.freeze();

  return registry;
}
