import 'dart:io';

import 'package:rudra_persistence_sqlite/rudra_persistence_sqlite.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:uuid/uuid.dart';

/// Composes portable SDK workflow operations with trusted macOS services.
///
/// Each operation opens one SQLite persistence owner and closes it before
/// returning. Trusted identity, private storage location, permissions and
/// workflow-ID generation belong to this host composition boundary.
///
/// Construction and read-only checks never create workflow persistence.
/// Only an explicit workflow submission may initialize storage.
///
/// Example:
/// ```dart
/// final workflows = ProductWorkflowComposition(
///   database_file: File('/private/test/rudra.sqlite'),
///   os_user_id_provider: () async => 'trusted-owner',
/// );
/// final current = await workflows.current();
/// ```
final class ProductWorkflowComposition {
  /// Creates composition with an injected [database_file] and identity source.
  ///
  /// [os_user_id_provider] must resolve a trusted platform identity. Tests
  /// may supply a deterministic identity and disposable database location.
  /// No persistence or filesystem I/O occurs during construction.
  ProductWorkflowComposition({
    required this.database_file,
    required Future<String> Function() os_user_id_provider,
  }) : _os_user_id_provider = os_user_id_provider;

  /// Creates production workflow composition for the local macOS host.
  ///
  /// The effective OS-user UID is obtained through `/usr/bin/id` and HOME
  /// selects only storage location. Throws on unsupported hosts, missing
  /// absolute HOME or unresolvable identity during a subsequent operation.
  /// Construction does not open or create SQLite persistence.
  factory ProductWorkflowComposition.for_current_host() {
    if (!Platform.isMacOS) {
      throw UnsupportedError(
        'Persistent workflow composition currently requires macOS.',
      );
    }

    final home = Platform.environment['HOME'];
    if (home == null || !home.startsWith('/')) {
      throw StateError('An absolute HOME directory is required.');
    }

    return ProductWorkflowComposition(
      database_file: File(
        '$home/Library/Application Support/Rudra/rudra.sqlite',
      ),
      os_user_id_provider: () async {
        final result = await Process.run('/usr/bin/id', ['-u']);
        if (result.exitCode != 0) {
          throw StateError('Unable to resolve the operating-system UID.');
        }

        final uid = int.tryParse((result.stdout as String).trim());
        if (uid == null || uid < 0) {
          throw StateError('Invalid operating-system UID.');
        }
        return 'macos-uid:$uid';
      },
    );
  }

  /// Stable host-provided file containing durable workflow persistence.
  final File database_file;

  /// Trusted host identity provider used for owner-scoped operations.
  final Future<String> Function() _os_user_id_provider;

  /// Reads the verified unfinished workflow without creating storage.
  ///
  /// Returns null for established absence, including when the database file
  /// has not yet been initialized. Journal and ownership integrity errors
  /// propagate instead of being interpreted as absence.
  Future<WorkflowSnapshot?> current() async {
    if (!await database_file.exists()) {
      return null;
    }

    final os_user_id = await _trusted_os_user_id();
    return _with_application(
      os_user_id: os_user_id,
      operation: (application) async {
        final state = await application.read_state();
        return state.workflows.current_workflow;
      },
    );
  }

  /// Requests workflow establishment at [target_id] and absolute [root].
  ///
  /// [idempotency_key] identifies the logical operation and is forwarded
  /// unchanged to the SDK application.
  ///
  /// Returns the durable operation outcome. Invalid arguments throw
  /// [ArgumentError] before storage initialization. Identity, persistence
  /// and infrastructure failures propagate.
  Future<WorkflowOperationOutcome> start({
    required String target_id,
    required TargetPath root,
    required String idempotency_key,
  }) async {
    if (!root.value.startsWith('/')) {
      throw ArgumentError.value(
        root.value,
        'root',
        'A local macOS workflow requires an absolute root.',
      );
    }

    if (target_id.trim().isEmpty) {
      throw ArgumentError.value(target_id, 'target_id');
    }

    _validate_operation_key(idempotency_key);

    final os_user_id = await _trusted_os_user_id();

    await _prepare_storage();

    return _with_application(
      os_user_id: os_user_id,
      operation: (application) => application.start(
        target_id: target_id,
        root: root,
        idempotency_key: idempotency_key,
      ),
    );
  }

  /// Requests termination of the explicitly identified [workflow_id].
  ///
  /// [idempotency_key] identifies the logical Stop operation and is
  /// forwarded unchanged to the SDK application.
  ///
  /// Returns the durable operation outcome, including business rejection
  /// when the requested workflow no longer exists.
  ///
  /// Throws [ArgumentError] for blank identifiers before storage
  /// initialization. Identity and infrastructure failures propagate.
  Future<WorkflowOperationOutcome> stop({
    required String workflow_id,
    required String idempotency_key,
  }) async {
    if (workflow_id.trim().isEmpty) {
      throw ArgumentError.value(workflow_id, 'workflow_id');
    }

    _validate_operation_key(idempotency_key);

    final os_user_id = await _trusted_os_user_id();

    await _prepare_storage();

    return _with_application(
      os_user_id: os_user_id,
      operation: (application) => application.stop(
        workflow_id: workflow_id,
        idempotency_key: idempotency_key,
      ),
    );
  }

  /// Prepares owner-restricted storage for an explicit durable submission.
  ///
  /// Creates the persistence directory if necessary and applies
  /// owner-only permissions.
  ///
  /// Throws [StateError] when directory permissions cannot be established.
  /// Filesystem failures propagate.
  Future<void> _prepare_storage() async {
    await database_file.parent.create(recursive: true);

    final permissions = await Process.run('/bin/chmod', [
      '700',
      database_file.parent.path,
    ]);

    if (permissions.exitCode != 0) {
      throw StateError('Unable to secure Rudra persistence directory.');
    }
  }

  /// Validates an [idempotency_key] before accessing persistence.
  ///
  /// Throws [ArgumentError] when the key is blank. The original key is
  /// preserved without normalization.
  static void _validate_operation_key(String idempotency_key) {
    if (idempotency_key.trim().isEmpty) {
      throw ArgumentError.value(idempotency_key, 'idempotency_key');
    }
  }

  /// Runs one SDK [operation] using a trusted owner and persistence lifetime.
  ///
  /// [os_user_id] was resolved through the host's identity provider before
  /// persistence access. Returns the awaited operation result and always
  /// closes SQLite, including when SDK validation or processing throws.
  Future<T> _with_application<T>({
    required String os_user_id,
    required Future<T> Function(WorkflowApplication) operation,
  }) async {
    final runtime = WorkflowRuntime.standard();
    final persistence = RudraSqlitePersistence(
      database_file: database_file,
      scope_id: 'rudra-cli:$os_user_id',
      runtime: runtime,
    );

    try {
      final application = WorkflowApplication(
        runtime: runtime,
        persistence: persistence,
        identity_provider: _CliWorkflowIdentityProvider(os_user_id),
        os_user_id: os_user_id,
      );
      return await operation(application);
    } finally {
      await persistence.close();
    }
  }

  /// Resolves and validates the host's authenticated OS-user identifier.
  ///
  /// Returns the original trusted identity. Blank values throw [StateError].
  Future<String> _trusted_os_user_id() async {
    final identity = await _os_user_id_provider();
    if (identity.trim().isEmpty) {
      throw StateError('Trusted OS-user identity must not be blank.');
    }
    return identity;
  }
}

/// Proposes trusted identities when the SDK establishes a new workflow.
///
/// The owner is fixed by host composition; the accepted Start supplies only
/// the target and root. Generating a candidate does not commit a workflow.
final class _CliWorkflowIdentityProvider implements WorkflowIdentityProvider {
  /// Creates a provider bound to the trusted [os_user_id].
  const _CliWorkflowIdentityProvider(this.os_user_id);

  /// Trusted host owner assigned to each proposed workflow identity.
  final String os_user_id;

  /// Proposes a fresh identity for a pending Start [submission].
  ///
  /// Returns a UUID-bound [WorkflowIdentity] preserving the accepted target
  /// and root. Other command types throw [StateError]. The SDK committer must
  /// revalidate owner and uniqueness before establishing the identity.
  @override
  Future<WorkflowIdentity> propose_identity(
    PendingWorkflowCommand submission,
  ) async {
    final command = submission.command;
    if (command is! WorkflowStartEvent) {
      throw StateError('Unsupported workflow identity request.');
    }

    return WorkflowIdentity(
      workflow_id: Uuid().v4(),
      os_user_id: os_user_id,
      target_id: command.target_id,
      root: command.root,
    );
  }
}
