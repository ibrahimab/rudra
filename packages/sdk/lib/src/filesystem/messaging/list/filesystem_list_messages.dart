import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import '../../inspection_issue.dart';

/// Requests admission of a directory inspection.
///
/// Inspection identifiers are allocated by the client and scoped
/// to the authenticated communication session.
///
/// Example:
/// ```dart
/// final request = FilesystemListOpenRequest(
///   inspection_id: 'inspection-001',
///   target_id: 'local-macos',
///   directory: TargetPath('/workspace'),
/// );
/// ```
final class FilesystemListOpenRequest
    implements Request<FilesystemListOpenResponse> {
  /// Creates a directory inspection request.
  ///
  /// [inspection_id] identifies the intended inspection.
  /// [target_id] identifies the requested filesystem environment.
  /// [directory] preserves the requested target-native directory.
  ///
  /// Throws [ArgumentError] for an invalid inspection identifier
  /// or blank target identifier.
  FilesystemListOpenRequest({
    required this.inspection_id,
    required this.target_id,
    required this.directory,
  }) {
    _require_inspection_id(inspection_id);

    if (target_id.trim().isEmpty) {
      throw ArgumentError.value(target_id, 'target_id');
    }
  }

  /// Client-assigned inspection identity.
  final String inspection_id;

  /// Requested configured filesystem target.
  final String target_id;

  /// Requested directory in target-native syntax.
  final TargetPath directory;
}

/// Confirms admission of a directory inspection.
///
/// Acceptance establishes an inspection lifecycle independently
/// of its eventual observations or completion status.
///
/// Example:
/// ```dart
/// final response = FilesystemListOpenResponse(
///   inspection_id: request.inspection_id,
/// );
/// ```
final class FilesystemListOpenResponse implements Response {
  /// Confirms admission of [inspection_id].
  ///
  /// Throws [ArgumentError] for an invalid inspection identifier.
  FilesystemListOpenResponse({required this.inspection_id}) {
    _require_inspection_id(inspection_id);
  }

  /// Identity of the admitted inspection.
  final String inspection_id;
}

/// Requests the next ordered batch of filesystem observations.
///
/// Each request advances one admitted inspection.
///
/// Example:
/// ```dart
/// final request = FilesystemListNextRequest(
///   inspection_id: 'inspection-001',
///   sequence: 1,
/// );
/// ```
final class FilesystemListNextRequest
    implements Request<FilesystemListBatchResponse> {
  /// Requests [sequence] from [inspection_id].
  ///
  /// Sequences begin at one and advance after successful delivery.
  ///
  /// Throws [ArgumentError] for an invalid inspection identifier
  /// or non-positive sequence.
  FilesystemListNextRequest({
    required this.inspection_id,
    required this.sequence,
  }) {
    _require_inspection_id(inspection_id);
    _require_sequence(sequence);
  }

  /// Identity of the inspection being advanced.
  final String inspection_id;

  /// Expected next observation batch sequence.
  final int sequence;
}

/// Describes the progress of an admitted filesystem inspection.
///
/// Terminal statuses describe the entire logical inspection,
/// including observations delivered in earlier batches.
///
/// Example:
/// ```dart
/// final status = FilesystemListBatchStatus.complete;
/// assert(status.is_terminal);
/// ```
enum FilesystemListBatchStatus {
  /// Additional inspection work remains.
  more,

  /// Inspection finished without incomplete observations.
  complete,

  /// Inspection finished with incomplete observations.
  incomplete;

  /// Whether this status terminates the logical inspection.
  bool get is_terminal => this != more;
}

/// Delivers one bounded batch of filesystem observations.
///
/// Successful entries and inspection issues retain their
/// respective observation ordering across successive batches.
///
/// Example:
/// ```dart
/// final response = FilesystemListBatchResponse(
///   inspection_id: 'inspection-001',
///   sequence: 1,
///   status: FilesystemListBatchStatus.complete,
///   entries: [],
///   issues: [],
/// );
/// ```
final class FilesystemListBatchResponse implements Response {
  /// Creates an immutable observation batch.
  ///
  /// [inspection_id] identifies the admitted inspection.
  /// [sequence] identifies its ordered observation batch.
  /// [status] identifies inspection progress or completion.
  /// [entries] contains successfully inspected entries.
  /// [issues] contains typed inspection failures.
  ///
  /// Throws [ArgumentError] for invalid identifiers, sequences,
  /// excessive observation counts or contradictory batch contents.
  FilesystemListBatchResponse({
    required this.inspection_id,
    required this.sequence,
    required this.status,
    required List<FilesystemEntry> entries,
    required List<InspectionIssue> issues,
  }) : entries = List<FilesystemEntry>.unmodifiable(entries),
       issues = List<InspectionIssue>.unmodifiable(issues) {
    _require_inspection_id(inspection_id);
    _require_sequence(sequence);

    if (observation_count > maximum_observations) {
      throw ArgumentError.value(
        observation_count,
        'observation_count',
        'Filesystem batch exceeds its observation capacity.',
      );
    }

    if (status == FilesystemListBatchStatus.more && observation_count == 0) {
      throw ArgumentError(
        'A non-terminal filesystem batch must contain observations.',
      );
    }

    if (status == FilesystemListBatchStatus.complete &&
        this.issues.isNotEmpty) {
      throw ArgumentError(
        'A complete inspection cannot contain inspection issues.',
      );
    }
  }

  /// Maximum combined entries and issues permitted in one batch.
  static const int maximum_observations = 128;

  /// Identity of the associated inspection.
  final String inspection_id;

  /// Ordered position within the associated inspection.
  final int sequence;

  /// Inspection progress or terminal completion status.
  final FilesystemListBatchStatus status;

  /// Successfully inspected entries in their observation order.
  final List<FilesystemEntry> entries;

  /// Typed inspection failures in their observation order.
  final List<InspectionIssue> issues;

  /// Combined number of entries and issues in this batch.
  int get observation_count => entries.length + issues.length;
}

/// Requests explicit retirement of a filesystem inspection.
///
/// Cancellation is scoped to the current authenticated session.
///
/// Example:
/// ```dart
/// final request = FilesystemListCancelRequest(
///   inspection_id: 'inspection-001',
/// );
/// ```
final class FilesystemListCancelRequest
    implements Request<FilesystemListCancelResponse> {
  /// Requests retirement of [inspection_id].
  ///
  /// Throws [ArgumentError] for an invalid inspection identifier.
  FilesystemListCancelRequest({required this.inspection_id}) {
    _require_inspection_id(inspection_id);
  }

  /// Identity of the inspection to retire.
  final String inspection_id;
}

/// Confirms retirement of a filesystem inspection.
///
/// Confirmation establishes that no resources remain owned by
/// the identified inspection within the authenticated session.
///
/// Example:
/// ```dart
/// final response = FilesystemListCancelResponse(
///   inspection_id: request.inspection_id,
/// );
/// ```
final class FilesystemListCancelResponse implements Response {
  /// Confirms retirement of [inspection_id].
  ///
  /// Throws [ArgumentError] for an invalid inspection identifier.
  FilesystemListCancelResponse({required this.inspection_id}) {
    _require_inspection_id(inspection_id);
  }

  /// Identity of the retired inspection.
  final String inspection_id;
}

/// Maximum length of a filesystem inspection identifier.
const int _maximum_inspection_id_length = 64;

/// Permitted characters in opaque inspection identifiers.
final RegExp _inspection_id_pattern = RegExp(r'^[A-Za-z0-9_-]+$');

/// Validates an opaque inspection [value].
///
/// Throws [ArgumentError] for unsupported characters or length.
void _require_inspection_id(String value) {
  final match = _inspection_id_pattern.firstMatch(value);

  if (value.length > _maximum_inspection_id_length ||
      match == null ||
      match.end != value.length) {
    throw ArgumentError.value(value, 'inspection_id');
  }
}

/// Validates an ordered batch [sequence].
///
/// Throws [ArgumentError] for non-positive sequence values.
void _require_sequence(int sequence) {
  if (sequence <= 0) {
    throw ArgumentError.value(sequence, 'sequence');
  }
}
