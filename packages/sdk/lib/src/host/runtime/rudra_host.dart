import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:rudra_communication/rudra_communication.dart';

import '../../state/publication/state_publication.dart';
import '../../state/rudra_state.dart';

import '../../messaging/application_message_codecs.dart';
import '../../messaging/application_request_context.dart';
import '../../messaging/application_request_handler_module.dart';
import '../../messaging/standard_messaging_modules.dart';

import '../../workflow/application/workflow_application.dart';

import '../../filesystem/application/filesystem_application.dart';
import '../../filesystem/messaging/list/filesystem_list_handlers.dart';

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
/// Retains one workflow application, authoritative state publication
/// and communication subsystem.
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
  /// [filesystem_application] supplies authoritative filesystem
  /// inspection against the configured target environment.
  ///
  /// Throws [StateError] for incompatible messaging configuration.
  /// Registration and communication construction failures propagate.
  ///
  /// Construction assembles configuration without binding endpoints,
  /// initializing SQLite or executing application operations.
  factory RudraHost({
    required WorkflowApplication application,
    required FilesystemApplication filesystem_application,
    required WorkflowStartValidator validate_start,
    HostCommunicationFactory? communication_factory,
  }) {
    // Use the same immutable runtime for execution and state codecs.
    final modules = standard_messaging_modules(
      workflow_runtime: application.runtime,
    );

    final codecs = create_application_message_codecs(modules: modules);

    final publication = StatePublication(
      generation: Uuid().v4(),
      observe_state: application.observe_state,
    );

    final filesystem_handlers = FilesystemListHandlers(
      application: filesystem_application,
    );

    final context = ApplicationRequestContext(
      application: application,
      publication: publication,
      validate_start: validate_start,
      filesystem_handlers: filesystem_handlers,
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

    return RudraHost._(
      application: application,
      publication: publication,
      filesystem_handlers: filesystem_handlers,
      communication: communication,
    );
  }

  /// Retains the configured application and owned host resources.
  ///
  /// [application] supplies authoritative application execution.
  /// [publication] owns verified application-state observation.
  /// [communication] owns authenticated communication execution.
  /// [filesystem_handlers] owns session-scoped filesystem inspections.
  ///
  /// Configuration has been validated before construction.
  RudraHost._({
    required WorkflowApplication application,
    required StatePublication publication,
    required FilesystemListHandlers filesystem_handlers,
    required this.communication,
  }) : _application = application,
       _publication = publication,
       _filesystem_handlers = filesystem_handlers;

  /// Authoritative application retained throughout host execution.
  final WorkflowApplication _application;

  /// Authoritative state publication owned by this host lifecycle.
  final StatePublication _publication;

  /// Authoritative filesystem inspection resources owned by this host.
  ///
  /// Retains active and draining inspections until resource disposal
  /// has been confirmed.
  final FilesystemListHandlers _filesystem_handlers;

  /// Whether publication resource disposal has been confirmed.
  ///
  /// False during execution and following unconfirmed disposal.
  bool _publication_released = true;

  /// Configured communication subsystem owned by this host.
  ///
  /// Exposes lifecycle information to trusted application composition.
  /// Communication execution and disposal remain host responsibilities.
  final Communication communication;

  /// Whether all host-owned resources have been successfully released.
  ///
  /// Returns true before execution and after confirmed communication
  /// and publication disposal.
  ///
  /// Trusted composition uses this boundary before releasing
  /// exclusive host ownership.
  bool get resources_released =>
      communication.resources_released &&
      _publication_released &&
      _filesystem_handlers.resources_released;

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
  /// before initial authoritative state publication.
  ///
  /// [on_ready] receives the first available verified application
  /// state before client sessions are admitted.
  ///
  /// Communication authorization uses the application's authenticated
  /// operating-system owner.
  ///
  /// Returns after communication disposal, admitted-handler draining
  /// and authoritative publication disposal.
  ///
  /// Throws [StateError] if this host has already been executed.
  /// Application initialization, observation, communication and
  /// resource disposal failures propagate.
  Future<void> run({
    required String scope_directory,
    required Future<void> shutdown,
    Future<void> Function(WorkflowApplication)? on_startup,
    void Function(RudraState)? on_ready,
  }) async {
    if (_has_run) {
      throw StateError('Host has already been run.');
    }

    _has_run = true;
    _publication_released = false;

    // Authoritative observation failure terminates the host rather
    // than allowing a generation with unavailable state to persist.
    final termination = Future.any<void>([shutdown, _publication.done]);

    termination.ignore();

    try {
      await communication.run(
        scope_directory: scope_directory,
        os_user_id: _application.os_user_id,
        shutdown: termination,
        on_startup: () async {
          await on_startup?.call(_application);

          await _publication.start();

          final initial = _publication.latest;

          if (initial == null) {
            // Readiness may have been followed immediately by source
            // failure. Preserve its authoritative failure result.
            await _publication.done;

            throw StateError('Authoritative publication is unavailable.');
          }

          on_ready?.call(initial.state);
        },
      );
    } finally {
      // Communication termination prevents additional remote admission.
      // Filesystem inspection and publication resources must both
      // be drained before exclusive host ownership can be released.
      try {
        await _filesystem_handlers.close();
      } finally {
        await _publication.close();

        _publication_released = true;
      }
    }

    // Preserve an authoritative failure even when external shutdown
    // completed concurrently with publication invalidation.
    await _publication.done;
  }
}
