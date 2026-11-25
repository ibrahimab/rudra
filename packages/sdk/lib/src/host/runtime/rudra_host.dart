import 'package:rudra_communication/rudra_communication.dart';

import '../../messaging/application_message_codecs.dart';
import '../../messaging/application_request_context.dart';
import '../../messaging/application_request_handler_module.dart';
import '../../messaging/standard_messaging_modules.dart';

import '../../workflow/application/workflow_application.dart';

/// Creates a substitute communication subsystem using host-owned
/// application messaging configuration.
///
/// [codecs] and [handlers] contain the validated, frozen application
/// registrations assembled by the host.
///
/// Returns an unused communication instance retaining both registries.
/// Its execution lifecycle transfers to the host.
///
/// The factory must not bind endpoints or execute application handlers.
typedef HostCommunicationFactory = Communication Function({
  required MessageCodecRegistry codecs,
  required RequestHandlerRegistry handlers,
});

/// Coordinates one authoritative Rudra host execution lifecycle.
///
/// Retains one workflow application and one communication subsystem.
///
/// The application supplies authoritative operations, trusted ownership
/// and workflow runtime configuration. Feature-owned messaging modules
/// contribute the codecs and handlers required for remote execution.
///
/// The caller retains ownership of the application's persistence resources.
///
/// Example:
/// ```dart
/// final host = RudraHost(
///   application: application,
///   validate_start: validate_target_root,
/// );
///
/// await host.run(
///   scope_directory: scope,
///   shutdown: shutdown.future,
/// );
/// ```
final class RudraHost {
  /// Creates a host bound to the configured [application].
  ///
  /// [validate_start] supplies trusted target-specific validation
  /// for workflow establishment requests.
  ///
  /// [communication_factory] optionally substitutes the default
  /// communication implementation using the host-owned registries.
  ///
  /// Throws [StateError] for incompatible messaging configuration.
  /// Registration and communication construction failures propagate.
  ///
  /// Construction assembles configuration without binding endpoints,
  /// initializing SQLite or executing application operations.
  factory RudraHost({
    required WorkflowApplication application,
    required WorkflowStartValidator validate_start,
    HostCommunicationFactory? communication_factory,
  }) {
    // Use the same immutable runtime for execution and state codecs.
    final modules = standard_messaging_modules(
      workflow_runtime: application.runtime,
    );

    final codecs = create_application_message_codecs(modules: modules);

    final context = ApplicationRequestContext(
      application: application,
      validate_start: validate_start,
    );

    final handlers = RequestHandlerRegistry();

    // Feature contributions determine available application handlers.
    // The host remains independent of individual request types.
    for (final module in modules.whereType<ApplicationRequestHandlerModule>()) {
      module.register_handlers(handlers, context);

      if (handlers.is_frozen) {
        throw StateError(
          'Application messaging module prematurely froze '
          'the handler registry: ${module.module_id}',
        );
      }
    }

    handlers.freeze(codecs: codecs);

    final communication = communication_factory == null
        ? Communication(codecs: codecs, handlers: handlers)
        : communication_factory(codecs: codecs, handlers: handlers);

    return RudraHost._(application: application, communication: communication);
  }

  /// Retains the configured [application] and owned [communication].
  ///
  /// Configuration has been validated before this constructor is invoked.
  RudraHost._({
    required WorkflowApplication application,
    required this.communication,
  }) : _application = application;

  /// Authoritative application retained throughout host execution.
  final WorkflowApplication _application;

  /// Configured communication subsystem owned by this host.
  ///
  /// Exposes lifecycle information to trusted application composition.
  /// Communication execution and disposal remain host responsibilities.
  final Communication communication;

  /// Whether this host has entered its execution lifecycle.
  bool _has_run = false;

  /// Executes the configured host lifecycle.
  ///
  /// [scope_directory] identifies the exclusively owned communication
  /// scope established by trusted application composition.
  ///
  /// [shutdown] supplies the external termination notification.
  ///
  /// [on_startup] optionally initializes the retained application
  /// before accepting client sessions.
  ///
  /// Communication authorization uses the application's authenticated
  /// operating-system owner.
  ///
  /// Returns after communication resource disposal and completion
  /// of previously admitted application handlers.
  ///
  /// Throws [StateError] if this host has already been executed.
  /// Application initialization and communication failures propagate.
  Future<void> run({
    required String scope_directory,
    required Future<void> shutdown,
    Future<void> Function(WorkflowApplication)? on_startup,
  }) async {
    if (_has_run) {
      throw StateError('Host has already been run.');
    }

    _has_run = true;

    await communication.run(
      scope_directory: scope_directory,
      os_user_id: _application.os_user_id,
      shutdown: shutdown,
      on_startup: on_startup == null ? null : () => on_startup(_application),
    );
  }
}
