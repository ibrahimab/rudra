import 'dart:io';

import 'package:rudra_sdk/rudra_sdk.dart';

/// Restores workflow history without initializing missing SQLite storage.
///
/// When the database has never existed during this adapter's lifetime,
/// missing storage establishes that no durable workflow history is present.
///
/// Once a database has been observed, its unexpected disappearance becomes
/// an explicit failure rather than being interpreted as workflow absence.
///
/// Existing databases are read through [WorkflowHistoryStore], preserving
/// SDK validation of the committed journal and ownership projection.
///
/// Example:
/// ```dart
/// final history_store = NonInitializingWorkflowHistoryStore(
///   database_file: database_file,
///   delegate: DriftWorkflowHistoryStore(database: database),
/// );
///
/// final evidence = await history_store.load_restoration_evidence(
///   os_user_id: trusted_os_user_id,
/// );
/// ```
final class NonInitializingWorkflowHistoryStore
    implements WorkflowHistoryStore {
  /// Creates a read-only guard around an authoritative history store.
  ///
  /// [database_file] identifies the SQLite file managed by composition.
  /// [delegate] retrieves consistent history when storage exists.
  ///
  /// Construction checks initial file existence but does not open SQLite,
  /// create directories, modify persistence or replay domain events.
  NonInitializingWorkflowHistoryStore({
    required File database_file,
    required WorkflowHistoryStore delegate,
  }) : _database_file = database_file,
       _delegate = delegate,
       _has_seen_database = database_file.existsSync();

  /// File containing authoritative SQLite workflow persistence.
  final File _database_file;

  /// Existing history reader used when durable storage is available.
  final WorkflowHistoryStore _delegate;

  /// Whether the database has been observed during this adapter's lifetime.
  bool _has_seen_database;

  /// Restores owner-scoped evidence without creating missing storage.
  ///
  /// [os_user_id] is the authenticated owner from trusted composition.
  ///
  /// Returns empty restoration evidence when storage has never existed.
  /// Otherwise returns the [WorkflowHistoryStore] delegate's evidence.
  ///
  /// Throws [ArgumentError] for a blank owner, [StateError] if previously
  /// available storage disappears, or propagates filesystem and delegate
  /// errors. No workflow processing or persistence writes occur here.
  @override
  Future<WorkflowRestorationEvidence> load_restoration_evidence({
    required String os_user_id,
  }) async {
    if (os_user_id.trim().isEmpty) {
      throw ArgumentError.value(os_user_id, 'os_user_id');
    }

    final exists = await _database_file.exists();

    if (!exists) {
      if (_has_seen_database) {
        throw StateError(
          'Previously available workflow persistence is missing.',
        );
      }

      return WorkflowRestorationEvidence(
        projected: null,
        other_histories: const [],
      );
    }

    _has_seen_database = true;

    return _delegate.load_restoration_evidence(os_user_id: os_user_id);
  }
}
