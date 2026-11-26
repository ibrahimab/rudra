import 'package:rudra_target_contracts/rudra_target_contracts.dart';

/// Serializes filesystem entries and their observed metadata.
///
/// Preserves target-native paths, entry classifications, filesystem
/// identities, permissions and nullable metadata.
///
/// Timestamps use canonical UTC ISO 8601 representations, preserving
/// microsecond precision.
///
/// Example:
/// ```dart
/// const codec = FilesystemEntryCodec();
/// final payload = codec.encode(entry);
/// final restored = codec.decode(payload);
///
/// print(restored.path.value);
/// ```
final class FilesystemEntryCodec {
  /// Creates the stateless filesystem entry codec.
  const FilesystemEntryCodec();

  /// Converts [entry] into its structured representation.
  ///
  /// Returns the original target-native path, entry kind and
  /// observed metadata. Unavailable metadata is represented by null.
  Map<String, Object?> encode(FilesystemEntry entry) {
    return {
      'path': entry.path.value,
      'kind': entry.kind.name,
      'metadata': _encode_metadata(entry.metadata),
    };
  }

  /// Reconstructs a filesystem entry from [payload].
  ///
  /// Returns a validated entry preserving the original observations.
  /// Throws [FormatException] for malformed representations,
  /// unexpected fields or invalid domain values.
  FilesystemEntry decode(Object? payload) {
    final fields = _require_fields(payload, const {'path', 'kind', 'metadata'});

    final path = fields['path'];
    final kind = fields['kind'];

    if (path is! String || kind is! String) {
      throw const FormatException('Invalid filesystem entry fields.');
    }

    try {
      return FilesystemEntry(
        path: TargetPath(path),
        kind: FilesystemEntryKind.values.byName(kind),
        metadata: _decode_metadata(fields['metadata']),
      );
    } on ArgumentError {
      throw const FormatException('Invalid filesystem entry values.');
    }
  }

  /// Encodes [metadata] while preserving unavailable observations.
  static Map<String, Object?> _encode_metadata(FilesystemMetadata metadata) {
    final identity = metadata.identity;
    final permissions = metadata.permissions;

    return {
      'logical_size_bytes': metadata.logical_size_bytes,
      'allocated_size_bytes': metadata.allocated_size_bytes,
      'created_at': metadata.created_at?.toIso8601String(),
      'modified_at': metadata.modified_at?.toIso8601String(),
      'accessed_at': metadata.accessed_at?.toIso8601String(),
      'identity': identity == null
          ? null
          : {
              'filesystem_id': identity.filesystem_id,
              'entry_id': identity.entry_id,
            },
      'permissions': permissions == null
          ? null
          : {
              'posix_mode': permissions.posix_mode,
              'effective_readable': permissions.effective_readable,
              'effective_writable': permissions.effective_writable,
              'effective_executable': permissions.effective_executable,
            },
    };
  }

  /// Reconstructs observed filesystem metadata from [payload].
  ///
  /// Nullable fields must be explicitly present in the representation.
  /// Domain constructors enforce their existing value invariants.
  static FilesystemMetadata _decode_metadata(Object? payload) {
    final fields = _require_fields(payload, const {
      'logical_size_bytes',
      'allocated_size_bytes',
      'created_at',
      'modified_at',
      'accessed_at',
      'identity',
      'permissions',
    });

    return FilesystemMetadata(
      logical_size_bytes: _nullable<int>(fields['logical_size_bytes']),
      allocated_size_bytes: _nullable<int>(fields['allocated_size_bytes']),
      created_at: _decode_timestamp(fields['created_at']),
      modified_at: _decode_timestamp(fields['modified_at']),
      accessed_at: _decode_timestamp(fields['accessed_at']),
      identity: _decode_identity(fields['identity']),
      permissions: _decode_permissions(fields['permissions']),
    );
  }

  /// Reconstructs an optional filesystem identity from [payload].
  ///
  /// Returns null when identity information was unavailable.
  /// Throws [FormatException] for malformed identity fields.
  static FilesystemIdentity? _decode_identity(Object? payload) {
    if (payload == null) {
      return null;
    }

    final fields = _require_fields(payload, const {
      'filesystem_id',
      'entry_id',
    });

    final filesystem_id = fields['filesystem_id'];
    final entry_id = fields['entry_id'];

    if (filesystem_id is! String || entry_id is! String) {
      throw const FormatException('Invalid filesystem identity fields.');
    }

    return FilesystemIdentity(filesystem_id: filesystem_id, entry_id: entry_id);
  }

  /// Reconstructs optional observed permissions from [payload].
  ///
  /// Preserves the distinction between false and unavailable
  /// permission observations.
  static FilesystemPermissions? _decode_permissions(Object? payload) {
    if (payload == null) {
      return null;
    }

    final fields = _require_fields(payload, const {
      'posix_mode',
      'effective_readable',
      'effective_writable',
      'effective_executable',
    });

    return FilesystemPermissions(
      posix_mode: _nullable<int>(fields['posix_mode']),
      effective_readable: _nullable<bool>(fields['effective_readable']),
      effective_writable: _nullable<bool>(fields['effective_writable']),
      effective_executable: _nullable<bool>(fields['effective_executable']),
    );
  }

  /// Reconstructs an optional canonical UTC timestamp.
  ///
  /// Throws [FormatException] when [payload] is not null or a
  /// canonical UTC ISO 8601 timestamp.
  static DateTime? _decode_timestamp(Object? payload) {
    if (payload == null) {
      return null;
    }

    if (payload is! String) {
      throw const FormatException('Invalid filesystem timestamp.');
    }

    final timestamp = DateTime.tryParse(payload);

    // Require the canonical representation to reject normalized
    // invalid dates and silently discarded fractional precision.
    if (timestamp == null ||
        !timestamp.isUtc ||
        timestamp.toIso8601String() != payload) {
      throw const FormatException('Invalid filesystem timestamp.');
    }

    return timestamp;
  }

  /// Returns [value] as its expected nullable representation.
  ///
  /// Throws [FormatException] when a non-null value has an
  /// incompatible type.
  static T? _nullable<T extends Object>(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is T) {
      return value;
    }

    throw const FormatException('Invalid filesystem metadata value.');
  }

  /// Validates the exact field set of a structured representation.
  ///
  /// Returns the validated [payload].
  /// Throws [FormatException] for missing or unexpected fields.
  static Map<String, Object?> _require_fields(
    Object? payload,
    Set<String> expected,
  ) {
    if (payload is! Map<String, Object?> ||
        payload.length != expected.length ||
        !expected.every(payload.containsKey)) {
      throw const FormatException('Invalid filesystem entry payload.');
    }

    return payload;
  }
}
