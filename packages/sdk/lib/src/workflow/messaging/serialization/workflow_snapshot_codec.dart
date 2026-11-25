import '../../states/workflow_lifecycle.dart';
import '../../states/workflow_slice.dart';
import '../../states/workflow_snapshot.dart';

import '../../workflow_runtime.dart';

import 'workflow_identity_codec.dart';

/// Serializes an immutable composite workflow snapshot.
///
/// Lifecycle definitions and feature-owned slice codecs are
/// resolved through the supplied workflow runtime.
///
/// Every registered domain slice must have a corresponding
/// serialization codec before this capability can be constructed.
///
/// Slice bindings are encoded in stable identifier order.
/// Unknown or incompatible representations fail explicitly.
///
/// Example:
/// ```dart
/// final codec = WorkflowSnapshotCodec(
///   runtime: WorkflowRuntime.standard(),
/// );
///
/// final restored = codec.decode(codec.encode(snapshot));
///
/// print(restored.version);
/// ```
final class WorkflowSnapshotCodec {
  /// Creates a snapshot codec using the supplied [runtime].
  ///
  /// The runtime provides registered lifecycle definitions,
  /// typed slice ownership and feature-owned serialization codecs.
  ///
  /// Throws [StateError] when a registered slice has no compatible
  /// codec in the supplied configuration.
  ///
  /// Construction does not serialize state or access persistence.
  WorkflowSnapshotCodec({required WorkflowRuntime runtime})
    : _runtime = runtime {
    for (final key in runtime.slice_keys.values) {
      final codec = runtime.slice_codecs[key.id];

      if (codec == null || codec.key != key) {
        throw StateError('Missing compatible workflow slice codec: ${key.id}.');
      }
    }
  }

  /// Immutable workflow configuration used for reconstruction.
  final WorkflowRuntime _runtime;

  /// Serializer responsible for immutable workflow identity.
  static const _identity_codec = WorkflowIdentityCodec();

  /// Converts [snapshot] into its structured representation.
  ///
  /// Returns its identity, committed version, registered lifecycle
  /// identifier and deterministically ordered slice representations.
  ///
  /// Throws [StateError] for unregistered lifecycle definitions,
  /// conflicting lifecycle metadata or incompatible slice bindings.
  ///
  /// Feature-owned serialization failures propagate.
  Map<String, Object?> encode(WorkflowSnapshot snapshot) {
    final lifecycle = _runtime.lifecycles[snapshot.lifecycle.id];

    if (lifecycle == null || lifecycle != snapshot.lifecycle) {
      throw StateError(
        'Unregistered or incompatible workflow lifecycle: '
        '${snapshot.lifecycle.id}.',
      );
    }

    // Registration and snapshot assembly order must not affect
    // the serialized representation of equivalent domain state.
    final bindings = snapshot.slice_bindings.toList()
      ..sort((left, right) {
        return left.key.id.compareTo(right.key.id);
      });

    return {
      'identity': _identity_codec.encode(snapshot.identity),
      'version': snapshot.version,
      'lifecycle': lifecycle.id,
      'slices': [for (final binding in bindings) _encode_slice(binding)],
    };
  }

  /// Reconstructs a composite workflow snapshot from [payload].
  ///
  /// Returns an immutable snapshot containing its registered lifecycle
  /// definition and concrete typed domain-slice bindings.
  ///
  /// Throws [FormatException] for malformed representations,
  /// unknown lifecycle or slice identifiers, unsupported schema
  /// versions, duplicate slice identities or invalid domain values.
  ///
  /// Feature-owned codec contract violations propagate as
  /// [StateError]. No partial snapshot is returned.
  ///
  /// Successful reconstruction does not establish journal authority.
  WorkflowSnapshot decode(Object? payload) {
    if (payload is! Map<String, Object?> || payload.length != 4) {
      throw const FormatException('Invalid workflow snapshot payload.');
    }

    final version = payload['version'];
    final lifecycle_id = payload['lifecycle'];
    final slices = payload['slices'];

    if (version is! int ||
        version <= 0 ||
        lifecycle_id is! String ||
        slices is! List<Object?>) {
      throw const FormatException('Invalid workflow snapshot fields.');
    }

    final identity = _identity_codec.decode(payload['identity']);
    final lifecycle = _decode_lifecycle(lifecycle_id);

    final bindings = <WorkflowSliceBinding<WorkflowSlice>>[];

    final seen_ids = <String>{};

    for (final slice_payload in slices) {
      bindings.add(_decode_slice(slice_payload, seen_ids));
    }

    return WorkflowSnapshot(
      identity: identity,
      version: version,
      lifecycle: lifecycle,
      slices: bindings,
    );
  }

  /// Serializes a registered domain-slice [binding].
  ///
  /// Returns its stable identifier, supported schema version
  /// and feature-owned payload representation.
  ///
  /// Throws [StateError] for unknown or incompatible bindings.
  Map<String, Object?> _encode_slice(
    WorkflowSliceBinding<WorkflowSlice> binding,
  ) {
    final key = binding.key;
    final registered_key = _runtime.slice_keys[key.id];
    final codec = _runtime.slice_codecs[key.id];

    if (registered_key == null ||
        registered_key != key ||
        codec == null ||
        codec.key != key) {
      throw StateError(
        'Unregistered or incompatible workflow slice: ${key.id}.',
      );
    }

    return {
      'id': key.id,
      'schema_version': codec.schema_version,
      'payload': codec.encode_binding(binding),
    };
  }

  /// Resolves the canonical lifecycle identified by [id].
  ///
  /// Returns the immutable definition supplied by the runtime.
  ///
  /// Throws [FormatException] for an unsupported lifecycle.
  WorkflowLifecycle _decode_lifecycle(String id) {
    final lifecycle = _runtime.lifecycles[id];

    if (lifecycle == null) {
      throw const FormatException('Unsupported workflow lifecycle.');
    }

    return lifecycle;
  }

  /// Reconstructs a typed slice binding from [payload].
  ///
  /// [seen_ids] tracks identifiers already encountered within
  /// the current snapshot representation.
  ///
  /// Returns the binding produced by the registered typed codec.
  ///
  /// Throws [FormatException] for malformed slice representations,
  /// duplicate identifiers or unsupported codec schema versions.
  ///
  /// Feature-owned codec contract violations propagate.
  WorkflowSliceBinding<WorkflowSlice> _decode_slice(
    Object? payload,
    Set<String> seen_ids,
  ) {
    if (payload is! Map<String, Object?> ||
        payload.length != 3 ||
        !payload.containsKey('payload')) {
      throw const FormatException('Invalid workflow slice representation.');
    }

    final id = payload['id'];
    final schema_version = payload['schema_version'];

    if (id is! String || schema_version is! int || schema_version <= 0) {
      throw const FormatException('Invalid workflow slice metadata.');
    }

    if (!seen_ids.add(id)) {
      throw const FormatException('Duplicate workflow slice identifier.');
    }

    final codec = _runtime.slice_codecs[id];

    if (codec == null) {
      throw const FormatException('Unsupported workflow slice identifier.');
    }

    if (schema_version != codec.schema_version) {
      throw const FormatException('Unsupported workflow slice schema version.');
    }

    // The registered adapter retains the concrete generic type
    // and validates the decoded value before creating its binding.
    return codec.decode_binding(payload['payload']);
  }
}
