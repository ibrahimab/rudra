import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import '../inspection_issue.dart';

import 'filesystem_observation.dart';

/// Coordinates authoritative read-only filesystem inspection.
///
/// Operates against one configured target through its supplied
/// inspection capability. Observations are produced lazily in
/// native enumeration order.
///
/// Example:
/// ```dart
/// final application = FilesystemApplication(
///   target_id: 'local-macos',
///   inspector: inspector,
/// );
///
/// await for (final observation in application.observe_directory(
///   directory: TargetPath('/workspace'),
/// )) {
///   print(observation.entry?.path.value);
/// }
/// ```
final class FilesystemApplication {
  /// Creates an application for one configured filesystem target.
  ///
  /// [target_id] identifies the configured filesystem environment.
  /// [inspector] supplies its target-native inspection capability.
  ///
  /// Throws [ArgumentError] for a blank target identifier.
  /// Construction retains configuration without inspecting files.
  FilesystemApplication({
    required this.target_id,
    required TargetInspector inspector,
  }) : _inspector = inspector {
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

  /// Inspection capability supplied by application composition.
  final TargetInspector _inspector;

  /// Lazily observes the immediate children of [directory].
  ///
  /// Returns a single-subscription stream of successful entries
  /// and typed inspection issues in native observation order.
  ///
  /// Individual child inspection failures preserve enumeration.
  /// Directory enumeration failures produce a terminal issue.
  ///
  /// Unexpected execution failures propagate through the stream.
  /// Cancellation releases underlying enumeration resources as
  /// promptly as the target implementation permits.
  ///
  /// Observations are read-only and do not constitute an atomic
  /// filesystem snapshot or authorization for destructive actions.
  Stream<FilesystemObservation> observe_directory({
    required TargetPath directory,
  }) async* {
    try {
      // Retain the target's lazy enumeration lifecycle rather
      // than collecting directory paths before inspection.
      await for (final child_path in _inspector.list_directory(directory)) {
        yield await _observe_entry(child_path);
      }
    } on TargetInspectionException catch (error) {
      // Deliver the terminal enumeration failure as a typed
      // observation before completing the stream.
      yield FilesystemObservation.failure(
        InspectionIssue.from_target_exception(error),
      );
    }
  }

  /// Inspects the filesystem entry identified by [path].
  ///
  /// Returns a successful entry observation or a typed inspection
  /// issue, allowing directory enumeration to continue.
  ///
  /// Unexpected inspection failures propagate to the caller.
  Future<FilesystemObservation> _observe_entry(TargetPath path) async {
    try {
      final entry = await _inspector.inspect(path);

      return FilesystemObservation.success(entry);
    } on TargetInspectionException catch (error) {
      return FilesystemObservation.failure(
        InspectionIssue.from_target_exception(error),
      );
    }
  }
}
