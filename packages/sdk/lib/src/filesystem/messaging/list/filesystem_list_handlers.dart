import 'dart:async';

import 'package:rudra_communication/rudra_communication.dart';

import '../../application/filesystem_application.dart';

import 'filesystem_list_inspection.dart';
import 'filesystem_list_messages.dart';

/// Owns filesystem inspections associated with authenticated sessions.
///
/// Coordinates inspection admission, advancement, expiration and
/// resource disposal independently of communication correlation.
///
/// Authorization is established by the application's request-handler
/// contribution before invoking these capabilities.
///
/// Example:
/// ```dart
/// final handlers = FilesystemListHandlers(
///   application: application,
/// );
///
/// final accepted = handlers.open(request, authorized_session);
///
/// final batch = await handlers.next(
///   FilesystemListNextRequest(
///     inspection_id: accepted.inspection_id,
///     sequence: 1,
///   ),
///   authorized_session,
/// );
/// ```
final class FilesystemListHandlers {
  /// Creates a filesystem inspection resource owner.
  ///
  /// [application] supplies authoritative filesystem observations.
  /// [maximum_per_session] bounds inspections owned by one session.
  /// [maximum_active] bounds inspections across this resource owner.
  /// [idle_timeout] bounds time between advancement requests.
  /// [advancement_timeout] bounds admitted advancement lifetime.
  ///
  /// Throws [ArgumentError] for non-positive limits or durations.
  /// Construction acquires no inspection resources.
  FilesystemListHandlers({
    required FilesystemApplication application,
    int maximum_per_session = default_maximum_per_session,
    int maximum_active = default_maximum_active,
    Duration idle_timeout = default_idle_timeout,
    Duration advancement_timeout = default_advancement_timeout,
  }) : _application = application,
       _maximum_per_session = maximum_per_session,
       _maximum_active = maximum_active,
       _idle_timeout = idle_timeout,
       _advancement_timeout = advancement_timeout {
    if (maximum_per_session <= 0) {
      throw ArgumentError.value(maximum_per_session, 'maximum_per_session');
    }

    if (maximum_active <= 0) {
      throw ArgumentError.value(maximum_active, 'maximum_active');
    }

    if (idle_timeout <= Duration.zero) {
      throw ArgumentError.value(idle_timeout, 'idle_timeout');
    }

    if (advancement_timeout <= Duration.zero) {
      throw ArgumentError.value(advancement_timeout, 'advancement_timeout');
    }
  }

  /// Default inspection capacity for one authenticated session.
  static const int default_maximum_per_session = 4;

  /// Default combined host inspection capacity.
  static const int default_maximum_active = 32;

  /// Default maximum lifetime without an advancement request.
  static const Duration default_idle_timeout = Duration(seconds: 30);

  /// Default maximum admitted advancement lifetime.
  static const Duration default_advancement_timeout = Duration(seconds: 20);

  /// Borrowed authoritative filesystem application.
  final FilesystemApplication _application;

  /// Maximum retained inspections per session.
  final int _maximum_per_session;

  /// Maximum retained inspections across the host.
  final int _maximum_active;

  /// Expiration duration between advancement requests.
  final Duration _idle_timeout;

  /// Expiration duration during admitted advancement.
  final Duration _advancement_timeout;

  /// Session-local inspection ownership indexed by object identity.
  ///
  /// Weak keys prevent retaining completed sessions unnecessarily.
  final Expando<_SessionInspections> _sessions = Expando(
    'rudra.filesystem.inspections',
  );

  /// Inspections whose resource disposal has not been confirmed.
  ///
  /// Includes both active and draining inspections.
  final Set<_InspectionBinding> _active = {};

  /// Whether this owner has permanently stopped admission.
  bool _closed = false;

  /// Retained resource-disposal result.
  Future<void>? _close_future;

  /// Whether every admitted inspection has released its resources.
  bool get resources_released => _active.isEmpty;

  /// Number of inspections retaining admission capacity.
  int get active_count => _active.length;

  /// Admits the requested inspection on authenticated [session].
  ///
  /// [request] supplies the directory and inspection identity.
  ///
  /// Returns confirmation with the configured target identity.
  ///
  /// Throws [StateError] for unavailable capacity, duplicate active
  /// identifiers or a terminated session.
  ///
  /// Native enumeration begins with the first advancement request.
  FilesystemListOpenResponse open(
    FilesystemListOpenRequest request,
    MessageSession session,
  ) {
    if (_closed) {
      throw StateError('Filesystem inspection admission is closed.');
    }

    final owner = _sessions[session] ??= _observe_session(session);

    if (owner.terminated) {
      throw StateError('Filesystem inspection session has terminated.');
    }

    if (owner.inspections.containsKey(request.inspection_id)) {
      throw StateError('Filesystem inspection is already admitted.');
    }

    if (owner.inspections.length >= _maximum_per_session ||
        _active.length >= _maximum_active) {
      throw StateError('Filesystem inspection capacity exhausted.');
    }

    final inspection = FilesystemListInspection(
      request: request,
      observations: _application.observe_directory(
        directory: request.directory,
      ),
    );

    final binding = _InspectionBinding(owner: owner, inspection: inspection);

    // Reserve capacity before making the inspection available
    // to subsequent advancement or cancellation requests.
    owner.inspections[inspection.inspection_id] = binding;

    _active.add(binding);

    _arm_expiration(binding, _idle_timeout);

    return FilesystemListOpenResponse(
      inspection_id: inspection.inspection_id,
      target_id: _application.target_id,
    );
  }

  /// Advances an inspection owned by authenticated [session].
  ///
  /// [request] supplies the inspection identity and expected sequence.
  ///
  /// Returns its next bounded observation batch.
  ///
  /// Throws [StateError] for unavailable ownership, invalid
  /// advancement admission or concurrent retirement.
  ///
  /// Terminal and failed inspections release their retained resources.
  Future<FilesystemListBatchResponse> next(
    FilesystemListNextRequest request,
    MessageSession session,
  ) async {
    final binding = _sessions[session]?.inspections[request.inspection_id];

    if (_closed || binding == null || binding.retirement != null) {
      throw StateError('Filesystem inspection is unavailable.');
    }

    final inspection = binding.inspection;

    // Invalid or concurrent requests must not refresh expiration
    // or retire an otherwise valid inspection.
    inspection.require_next(request.sequence);

    _arm_expiration(binding, _advancement_timeout);

    try {
      final response = await inspection.next(sequence: request.sequence);

      if (binding.retirement != null) {
        throw StateError('Filesystem inspection was retired.');
      }

      if (response.status.is_terminal) {
        await _retire(binding);
      } else {
        _arm_expiration(binding, _idle_timeout);
      }

      return response;
    } catch (_) {
      await _retire(binding);

      rethrow;
    }
  }

  /// Retires the inspection identified by [request] on [session].
  ///
  /// Returns confirmation after retained resources have been released.
  ///
  /// An absent inspection is already retired within this session.
  /// Disposal failures propagate rather than confirming retirement.
  Future<FilesystemListCancelResponse> cancel(
    FilesystemListCancelRequest request,
    MessageSession session,
  ) async {
    final binding = _sessions[session]?.inspections[request.inspection_id];

    if (binding != null) {
      await _retire(binding);
    }

    return FilesystemListCancelResponse(inspection_id: request.inspection_id);
  }

  /// Permanently closes admission and drains retained inspections.
  ///
  /// Returns after all owned inspection resources have been released.
  ///
  /// Repeated calls return the retained disposal result.
  /// Disposal failures propagate and retain unconfirmed ownership.
  Future<void> close() {
    _closed = true;

    return _close_future ??= Future.wait<void>([
      for (final binding in _active.toList()) _retire(binding),
    ]).then<void>((_) {});
  }

  /// Creates inspection ownership associated with [session].
  ///
  /// Returns a session-local owner observing communication termination.
  _SessionInspections _observe_session(MessageSession session) {
    final owner = _SessionInspections();

    session.done
        .then<void>(
          (_) => _disconnect(owner),
          onError: (Object error, StackTrace stack_trace) {
            return _disconnect(owner);
          },
        )
        .ignore();

    return owner;
  }

  /// Prohibits admission and retires inspections owned by [owner].
  ///
  /// Returns after all associated inspection retirement has settled.
  Future<void> _disconnect(_SessionInspections owner) async {
    owner.terminated = true;

    await Future.wait<void>([
      for (final binding in owner.inspections.values.toList()) _retire(binding),
    ]);
  }

  /// Establishes expiration of [binding] after [duration].
  ///
  /// Replaces the previous idle or advancement expiration.
  void _arm_expiration(_InspectionBinding binding, Duration duration) {
    binding.expiration?.cancel();

    binding.expiration = Timer(duration, () => _retire(binding).ignore());
  }

  /// Initiates retirement of [binding] exactly once.
  ///
  /// Returns its retained resource-disposal result.
  Future<void> _retire(_InspectionBinding binding) {
    binding.expiration?.cancel();

    return binding.retirement ??= _dispose(binding);
  }

  /// Disposes [binding] and releases its admission capacity.
  ///
  /// Failed disposal retains the binding and its resource ownership.
  Future<void> _dispose(_InspectionBinding binding) async {
    await binding.inspection.close();

    binding.owner.inspections.remove(binding.inspection.inspection_id);

    _active.remove(binding);
  }
}

/// Retains inspection ownership for one authenticated session.
final class _SessionInspections {
  /// Inspections retaining capacity within this session.
  final Map<String, _InspectionBinding> inspections = {};

  /// Whether communication termination has prohibited further admission.
  bool terminated = false;
}

/// Associates an inspection with its session and disposal lifecycle.
final class _InspectionBinding {
  /// Creates ownership of [inspection] within [owner].
  _InspectionBinding({required this.owner, required this.inspection});

  /// Session-local owner of this inspection.
  final _SessionInspections owner;

  /// Bounded filesystem observation lifecycle.
  final FilesystemListInspection inspection;

  /// Current idle or advancement expiration timer.
  Timer? expiration;

  /// Retained inspection retirement result.
  Future<void>? retirement;
}
