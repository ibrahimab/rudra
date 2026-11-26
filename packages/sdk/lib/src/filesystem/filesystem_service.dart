import 'package:rudra_target_contracts/rudra_target_contracts.dart';
import 'package:uuid/uuid.dart';

import '../client/client_connection.dart';

import 'directory_listing.dart';
import 'inspection_issue.dart';

import 'messaging/list/filesystem_list_messages.dart';

/// Provides host-backed read-only filesystem inspection.
///
/// Filesystem operations execute through the SDK's shared authenticated
/// connection against one configured filesystem target.
///
/// Bounded observation batches are assembled into immutable directory
/// listings independently of frontend presentation.
///
/// Example:
/// ```dart
/// final listing = await sdk.filesystem.list(
///   directory: TargetPath('/workspace'),
/// );
///
/// print(listing.entries.length);
/// print(listing.is_complete);
/// ```
final class FilesystemService {
  /// Creates a filesystem service for the configured [target_id].
  ///
  /// [connection] supplies authenticated application request execution.
  /// Its lifecycle remains owned by the composing SDK.
  ///
  /// Throws [ArgumentError] for a blank target identifier.
  /// Construction does not establish communication or inspect files.
  FilesystemService({
    required this.target_id,
    required ClientConnection connection,
  }) : _connection = connection {
    if (target_id.trim().isEmpty) {
      throw ArgumentError.value(
        target_id,
        'target_id',
        'The target identifier must not be blank.',
      );
    }
  }

  /// Identifier of the configured filesystem environment.
  final String target_id;

  /// Borrowed authenticated application request capability.
  final ClientConnection _connection;

  /// Lists and inspects the immediate children of [directory].
  ///
  /// The directory must use absolute target-native path syntax.
  ///
  /// Returns an immutable directory listing containing successful
  /// entries, typed inspection issues and authoritative completion
  /// status.
  ///
  /// All requests belonging to the inspection remain bound to
  /// the same authenticated communication session.
  ///
  /// Throws [StateError] when connectivity is unavailable, replaced,
  /// or the host returns inconsistent inspection metadata.
  ///
  /// Communication and remote execution failures propagate.
  /// Failed transfers are explicitly retired where possible.
  ///
  /// The complete listing is accumulated in memory before returning.
  /// Filesystem observations are not atomic snapshots.
  Future<DirectoryListing> list({required TargetPath directory}) async {
    final session = _connection.require_session();

    final inspection_id = Uuid().v4();

    final entries = <FilesystemEntry>[];
    final issues = <InspectionIssue>[];

    try {
      final accepted = await _connection.request(
        FilesystemListOpenRequest(
          inspection_id: inspection_id,
          target_id: target_id,
          directory: directory,
        ),
        session: session,
      );

      if (accepted.inspection_id != inspection_id) {
        throw StateError('Filesystem inspection admission mismatch.');
      }

      var sequence = 1;

      while (true) {
        final batch = await _connection.request(
          FilesystemListNextRequest(
            inspection_id: inspection_id,
            sequence: sequence,
          ),
          session: session,
        );

        // Validate the logical inspection and batch position
        // before accepting any returned observations.
        if (batch.inspection_id != inspection_id ||
            batch.sequence != sequence) {
          throw StateError('Filesystem observation batch mismatch.');
        }

        entries.addAll(batch.entries);
        issues.addAll(batch.issues);

        if (batch.status.is_terminal) {
          final is_complete =
              batch.status == FilesystemListBatchStatus.complete;

          if (is_complete && issues.isNotEmpty) {
            throw StateError('Filesystem inspection completion mismatch.');
          }

          return DirectoryListing(
            target_id: target_id,
            directory: directory,
            entries: entries,
            issues: issues,
            is_complete: is_complete,
          );
        }

        sequence++;
      }
    } catch (_) {
      // Admission may have succeeded even when its response
      // was lost. Retire the original inspection identifier
      // without submitting another inspection operation.
      try {
        final cancelled = await _connection.request(
          FilesystemListCancelRequest(inspection_id: inspection_id),
          session: session,
        );

        if (cancelled.inspection_id != inspection_id) {
          throw StateError('Filesystem inspection cancellation mismatch.');
        }
      } catch (_) {
        // When retirement cannot be confirmed, terminate the
        // original session rather than leave an abandoned
        // inspection attached to an otherwise usable session.
        try {
          await session.close();
        } catch (_) {
          // Preserve the original application failure.
          // Connection ownership retains disposal verification.
        }
      }

      rethrow;
    }
  }
}
