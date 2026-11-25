import 'dart:io';

import 'package:rudra_sdk/rudra_sdk.dart';

/// Guards durable submission-resolution reads against initialization
/// of missing SQLite storage.
///
/// A database that has never been observed contains no accessible
/// accepted submissions. Unexpected disappearance of previously
/// observed storage is treated as an integrity failure.
final class NonInitializingWorkflowSubmissionStatusReader
    implements WorkflowSubmissionStatusReader {
  /// Creates a non-initializing reader for [database_file].
  ///
  /// [delegate] supplies authoritative resolution reads when storage
  /// is available.
  ///
  /// Construction observes file existence without opening SQLite
  /// or initializing persistence.
  NonInitializingWorkflowSubmissionStatusReader({
    required File database_file,
    required WorkflowSubmissionStatusReader delegate,
  }) : _database_file = database_file,
       _delegate = delegate,
       _has_seen_database = database_file.existsSync();

  /// File containing durable submission and journal evidence.
  final File _database_file;

  /// Authoritative resolution reader for existing storage.
  final WorkflowSubmissionStatusReader _delegate;

  /// Whether storage has been observed during this reader's lifetime.
  bool _has_seen_database;

  /// Reads the durable resolution identified by [receipt].
  ///
  /// Returns null without initializing storage when the database has
  /// never been observed. Otherwise delegates to the authoritative reader.
  ///
  /// Throws [StateError] if previously observed storage disappears.
  /// Filesystem and resolution-integrity failures propagate.
  @override
  Future<WorkflowSubmissionResolution?> status_for(
    EventSubmissionReceipt receipt,
  ) async {
    final exists = await _database_file.exists();

    if (!exists) {
      if (_has_seen_database) {
        throw StateError(
          'Previously available workflow persistence is missing.',
        );
      }

      return null;
    }

    _has_seen_database = true;

    return _delegate.status_for(receipt);
  }
}
