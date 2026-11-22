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
/// Only an explicit Start may initialize the storage directory.
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

  /// Explicitly establishes a workflow at [target_id] and absolute [root].
  ///
  /// MacOS path validation precedes persistence initialization. The storage
  /// directory is created with owner-only permissions before opening SQLite.
  /// Returns a committed SDK [WorkflowSnapshot]. SDK business conflicts and
  /// persistence errors propagate without fabricating successful outcomes.
  Future<WorkflowSnapshot> start({
    required String target_id,
    required TargetPath root,
  }) async {
    if (!root.value.startsWith('/')) {
      throw ArgumentError.value(
        root.value,
        'root',
        'A local macOS workflow requires an absolute root.',
      );
    }

    // Resolve ownership before creating any persistence directory.
    final os_user_id = await _trusted_os_user_id();

    // Only explicit Start may initialize and secure the storage directory.
    await database_file.parent.create(recursive: true);
    final permissions = await Process.run('/bin/chmod', [
      '700',
      database_file.parent.path,
    ]);
    if (permissions.exitCode != 0) {
      throw StateError('Unable to secure Rudra persistence directory.');
    }

    return _with_application(
      os_user_id: os_user_id,
      operation: (application) =>
          application.start(target_id: target_id, root: root),
    );
  }

  /// Explicitly stops the owner's current unfinished workflow.
  ///
  /// [expected_workflow_id] optionally guards the workflow previously shown
  /// by a frontend. Empty identifiers throw [ArgumentError]. Missing storage
  /// yields a typed conflict without creating a database. Returns the exact
  /// workflow ID confirmed by committed terminal journal evidence.
  Future<String> stop({String? expected_workflow_id}) async {
    if (expected_workflow_id != null && expected_workflow_id.trim().isEmpty) {
      throw ArgumentError.value(
        expected_workflow_id,
        'expected_workflow_id',
        'Expected workflow identifier must not be blank.',
      );
    }

    if (!await database_file.exists()) {
      throw const WorkflowStopRejectedException(
        code: WorkflowRejectionCode.workflow_not_active,
      );
    }

    final os_user_id = await _trusted_os_user_id();
    return _with_application(
      os_user_id: os_user_id,
      operation: (application) =>
          application.stop(expected_workflow_id: expected_workflow_id),
    );
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
