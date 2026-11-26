import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import '../inspection_issue.dart';

/// Represents one observation produced during filesystem inspection.
///
/// Contains exactly one successful entry or typed inspection issue.
///
/// Example:
/// ```dart
/// final observation = FilesystemObservation.success(entry);
/// print(observation.entry?.path.value);
/// ```
final class FilesystemObservation {
  /// Creates a successful observation containing [entry].
  const FilesystemObservation.success(FilesystemEntry entry)
    : entry = entry,
      issue = null;

  /// Creates an unsuccessful observation containing [issue].
  const FilesystemObservation.failure(InspectionIssue issue)
    : entry = null,
      issue = issue;

  /// Successfully inspected filesystem entry, when available.
  final FilesystemEntry? entry;

  /// Typed failure associated with an unsuccessful observation.
  final InspectionIssue? issue;
}
