import 'package:rudra_communication/rudra_communication.dart';

import 'application_messaging_module.dart';
import 'application_request_context.dart';

/// Extends a feature-owned messaging contribution with local
/// application request execution.
///
/// Clients may consume the module's codecs without registering
/// its request handlers.
///
/// Hosts register both capabilities from the same feature contribution.
abstract interface class ApplicationRequestHandlerModule
    implements ApplicationMessagingModule {
  /// Contributes local request handlers to [registry].
  ///
  /// [context] supplies the trusted application capabilities shared
  /// by all handlers in the host configuration.
  ///
  /// Registration retains execution callbacks without invoking
  /// application operations.
  ///
  /// Implementations must leave registry finalization to the
  /// composition boundary.
  ///
  /// Registration failures propagate to the caller.
  void register_handlers(
    RequestHandlerRegistry registry,
    ApplicationRequestContext context,
  );
}
