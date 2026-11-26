import 'dart:async';

import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import '../../application/filesystem_observation.dart';
import '../../inspection_issue.dart';

import 'codecs/filesystem_list_codecs.dart';
import 'filesystem_list_messages.dart';

/// Produces ordered, bounded batches from one filesystem observation.
///
/// Owns the observation stream iterator throughout the inspection
/// lifecycle, including cancellation and terminal resource disposal.
///
/// Session ownership and inspection admission capacity belong to
/// the surrounding request-handler lifecycle.
///
/// Example:
/// ```dart
/// final inspection = FilesystemListInspection(
///   request: request,
///   observations: application.observe_directory(
///     directory: request.directory,
///   ),
/// );
///
/// try {
///   final batch = await inspection.next(sequence: 1);
///   print(batch.observation_count);
/// } finally {
///   await inspection.close();
/// }
/// ```
final class FilesystemListInspection {
  /// Creates a bounded inspection for an admitted [request].
  ///
  /// [observations] supplies the single-subscription observation stream.
  /// [work_budget] bounds cooperative batch work between observations.
  ///
  /// Throws [ArgumentError] for a non-positive work budget.
  /// Construction does not subscribe to the observation stream.
  FilesystemListInspection({
    required FilesystemListOpenRequest request,
    required Stream<FilesystemObservation> observations,
    Duration work_budget = default_work_budget,
  }) : inspection_id = request.inspection_id,
       _observations = observations,
       _work_budget = work_budget {
    if (work_budget <= Duration.zero) {
      throw ArgumentError.value(work_budget, 'work_budget');
    }
  }

  /// Default cooperative work budget for one advancement.
  static const Duration default_work_budget = Duration(seconds: 1);

  /// Serializer used to evaluate batch payload capacity.
  static const _codec = FilesystemListBatchResponseCodec();

  /// Opaque identity of this admitted inspection.
  final String inspection_id;

  /// Source of authoritative filesystem observations.
  final Stream<FilesystemObservation> _observations;

  /// Cooperative batch work budget.
  final Duration _work_budget;

  /// Lazily acquired observation stream iterator.
  StreamIterator<FilesystemObservation>? _iterator;

  /// Observation retained when it cannot fit in the current batch.
  FilesystemObservation? _pending;

  /// Sequence required by the next admitted advancement.
  int _next_sequence = 1;

  /// Whether the source has reached its terminal position.
  bool _source_exhausted = false;

  /// Whether any accepted observation contained an issue.
  bool _has_issues = false;

  /// Whether further advancement is permanently prohibited.
  bool _retired = false;

  /// Completion signal for the currently admitted advancement.
  Completer<void>? _advancement;

  /// Retained iterator resource-disposal result.
  Future<void>? _release_future;

  /// Retained explicit closure result.
  Future<void>? _close_future;

  /// Whether this inspection has been permanently retired.
  bool get is_retired => _retired;

  /// Validates admission of the requested [sequence].
  ///
  /// Throws [StateError] for retired inspections, concurrent
  /// advancement or an unexpected sequence.
  ///
  /// Admission validation does not advance the observation source.
  void require_next(int sequence) {
    _require_active();

    if (_advancement != null) {
      throw StateError('Filesystem inspection is already advancing.');
    }

    if (sequence != _next_sequence) {
      throw StateError('Unexpected filesystem batch sequence.');
    }
  }

  /// Produces the next observation batch identified by [sequence].
  ///
  /// Returns a bounded batch with an explicit continuation or
  /// terminal status.
  ///
  /// Throws [StateError] when advancement cannot be admitted.
  /// Throws [FormatException] when an individual observation
  /// cannot fit within the protocol payload ceiling.
  ///
  /// Unexpected source and disposal failures propagate and
  /// permanently retire the inspection.
  Future<FilesystemListBatchResponse> next({required int sequence}) async {
    require_next(sequence);

    // Claim advancement ownership before yielding to the
    // observation stream or another lifecycle operation.
    final advancement = Completer<void>();

    _advancement = advancement;

    try {
      final response = await _build_batch(sequence);

      _require_active();

      if (response.status.is_terminal) {
        _retired = true;

        await _release_iterator();
      } else {
        _next_sequence++;
      }

      return response;
    } catch (_) {
      _retired = true;

      await _release_iterator();

      rethrow;
    } finally {
      _advancement = null;

      advancement.complete();
    }
  }

  /// Permanently retires this inspection.
  ///
  /// Cancels retained enumeration and waits for admitted advancement
  /// and iterator disposal to settle.
  ///
  /// Repeated calls return the retained closure result.
  /// Native operations that cannot be interrupted may delay closure.
  /// Resource disposal failures propagate.
  Future<void> close() {
    _retired = true;

    return _close_future ??= _close();
  }

  /// Builds one batch at the admitted [sequence].
  ///
  /// Retains an observation for the next batch when admitting it
  /// would exceed the current payload capacity.
  Future<FilesystemListBatchResponse> _build_batch(int sequence) async {
    final entries = <FilesystemEntry>[];
    final issues = <InspectionIssue>[];

    final elapsed = Stopwatch()..start();

    /// Creates the current batch with the specified [status].
    FilesystemListBatchResponse create_response(
      FilesystemListBatchStatus status,
    ) {
      return FilesystemListBatchResponse(
        inspection_id: inspection_id,
        sequence: sequence,
        status: status,
        entries: entries,
        issues: issues,
      );
    }

    while (entries.length + issues.length <
        FilesystemListBatchResponse.maximum_observations) {
      _require_active();

      // Yield a non-empty batch when its cooperative work
      // budget has been consumed.
      if ((entries.isNotEmpty || issues.isNotEmpty) &&
          elapsed.elapsed >= _work_budget) {
        break;
      }

      final observation = await _next_observation();

      _require_active();

      if (observation == null) {
        break;
      }

      final entry = observation.entry;

      if (entry != null) {
        entries.add(entry);
      } else {
        issues.add(observation.issue!);
      }

      final candidate = create_response(FilesystemListBatchStatus.more);

      if (_codec.payload_size(candidate) >
          FilesystemListBatchResponseCodec.maximum_payload_bytes) {
        // Retain the original observation rather than discard
        // information or restart enumeration.
        if (entry != null) {
          entries.removeLast();
        } else {
          issues.removeLast();
        }

        if (entries.isEmpty && issues.isEmpty) {
          throw const FormatException(
            'Filesystem observation exceeds batch payload capacity.',
          );
        }

        _pending = observation;

        break;
      }

      if (observation.issue != null) {
        _has_issues = true;
      }
    }

    if (_source_exhausted) {
      final terminal = create_response(
        _has_issues
            ? FilesystemListBatchStatus.incomplete
            : FilesystemListBatchStatus.complete,
      );

      // Terminal status names can occupy more bytes than the
      // continuation status. Deliver a separate empty terminal
      // batch if the longer status would exceed capacity.
      if (_codec.payload_size(terminal) <=
          FilesystemListBatchResponseCodec.maximum_payload_bytes) {
        return terminal;
      }
    }

    return create_response(FilesystemListBatchStatus.more);
  }

  /// Retrieves the next observation or null at normal stream completion.
  ///
  /// Consumes any retained lookahead before advancing enumeration.
  Future<FilesystemObservation?> _next_observation() async {
    final pending = _pending;

    if (pending != null) {
      _pending = null;

      return pending;
    }

    if (_source_exhausted) {
      return null;
    }

    final iterator = _iterator ??= StreamIterator<FilesystemObservation>(
      _observations,
    );

    final available = await iterator.moveNext();

    // Cancellation may settle an outstanding moveNext without
    // establishing normal source exhaustion.
    _require_active();

    if (!available) {
      _source_exhausted = true;

      return null;
    }

    return iterator.current;
  }

  /// Rejects execution after permanent inspection retirement.
  ///
  /// Throws [StateError] when further observation delivery
  /// has been invalidated.
  void _require_active() {
    if (_retired) {
      throw StateError('Filesystem inspection has been retired.');
    }
  }

  /// Releases the iterator exactly once.
  ///
  /// Returns the retained disposal result, including failures.
  Future<void> _release_iterator() {
    _pending = null;

    return _release_future ??= _iterator?.cancel() ?? Future<void>.value();
  }

  /// Cancels enumeration and drains admitted advancement.
  ///
  /// Returns after resource disposal and advancement settle.
  Future<void> _close() async {
    final advancement = _advancement?.future;

    try {
      await _release_iterator();
    } finally {
      if (advancement != null) {
        await advancement;
      }
    }
  }
}
