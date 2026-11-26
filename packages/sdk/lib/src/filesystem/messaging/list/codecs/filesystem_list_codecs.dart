import 'dart:convert';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import '../../serialization/filesystem_entry_codec.dart';
import '../../serialization/inspection_issue_codec.dart';

import '../filesystem_list_messages.dart';

/// Serializes directory inspection admission requests.
///
/// Example:
/// ```dart
/// const codec = FilesystemListOpenRequestCodec();
/// final restored = codec.decode(codec.encode(request));
/// print(restored.directory.value);
/// ```
final class FilesystemListOpenRequestCodec
    implements MessageCodec<FilesystemListOpenRequest> {
  /// Creates the stateless inspection admission request codec.
  const FilesystemListOpenRequestCodec();

  /// Stable version 1 wire identifier.
  @override
  String get type_id => 'rudra.filesystem.list.open.request.v1';

  /// Returns the inspection identity, target and directory
  /// represented by [message].
  @override
  Map<String, Object?> encode(FilesystemListOpenRequest message) {
    return {
      'inspection_id': message.inspection_id,
      'target_id': message.target_id,
      'directory': message.directory.value,
    };
  }

  /// Reconstructs an admission request from [payload].
  ///
  /// Throws [FormatException] for invalid fields or values.
  @override
  FilesystemListOpenRequest decode(Object? payload) {
    return _decode(
      payload,
      const {'inspection_id', 'target_id', 'directory'},
      (fields) => FilesystemListOpenRequest(
        inspection_id: _string(fields, 'inspection_id'),
        target_id: _string(fields, 'target_id'),
        directory: TargetPath(_string(fields, 'directory')),
      ),
    );
  }
}

/// Serializes directory inspection admission responses.
///
/// Example:
/// ```dart
/// const codec = FilesystemListOpenResponseCodec();
/// final payload = codec.encode(response);
/// ```
final class FilesystemListOpenResponseCodec
    implements MessageCodec<FilesystemListOpenResponse> {
  /// Creates the stateless inspection admission response codec.
  const FilesystemListOpenResponseCodec();

  /// Stable version 1 wire identifier.
  @override
  String get type_id => 'rudra.filesystem.list.open.response.v1';

  /// Returns the admitted inspection identity from [message].
  @override
  Map<String, Object?> encode(FilesystemListOpenResponse message) {
    return {'inspection_id': message.inspection_id};
  }

  /// Reconstructs an admission response from [payload].
  ///
  /// Throws [FormatException] for invalid fields or identifiers.
  @override
  FilesystemListOpenResponse decode(Object? payload) {
    return _decode(
      payload,
      const {'inspection_id'},
      (fields) => FilesystemListOpenResponse(
        inspection_id: _string(fields, 'inspection_id'),
      ),
    );
  }
}

/// Serializes requests for subsequent filesystem observations.
///
/// Example:
/// ```dart
/// const codec = FilesystemListNextRequestCodec();
/// final restored = codec.decode(codec.encode(request));
/// print(restored.sequence);
/// ```
final class FilesystemListNextRequestCodec
    implements MessageCodec<FilesystemListNextRequest> {
  /// Creates the stateless next-batch request codec.
  const FilesystemListNextRequestCodec();

  /// Stable version 1 wire identifier.
  @override
  String get type_id => 'rudra.filesystem.list.next.request.v1';

  /// Returns the inspection identity and expected batch sequence
  /// represented by [message].
  @override
  Map<String, Object?> encode(FilesystemListNextRequest message) {
    return {
      'inspection_id': message.inspection_id,
      'sequence': message.sequence,
    };
  }

  /// Reconstructs a next-batch request from [payload].
  ///
  /// Throws [FormatException] for invalid fields or values.
  @override
  FilesystemListNextRequest decode(Object? payload) {
    return _decode(
      payload,
      const {'inspection_id', 'sequence'},
      (fields) => FilesystemListNextRequest(
        inspection_id: _string(fields, 'inspection_id'),
        sequence: _integer(fields, 'sequence'),
      ),
    );
  }
}

/// Serializes bounded batches of filesystem observations.
///
/// Uses the existing feature-owned entry and inspection issue
/// representations. The version 1 payload has an explicit
/// UTF-8 JSON size ceiling independently of transport framing.
///
/// Example:
/// ```dart
/// const codec = FilesystemListBatchResponseCodec();
/// final size = codec.payload_size(response);
/// final payload = codec.encode(response);
/// print(size);
/// ```
final class FilesystemListBatchResponseCodec
    implements MessageCodec<FilesystemListBatchResponse> {
  /// Creates the stateless observation batch codec.
  const FilesystemListBatchResponseCodec();

  /// Maximum serialized version 1 batch payload size in bytes.
  ///
  /// Leaves headroom for communication envelope metadata under
  /// the standard communication frame configuration.
  static const int maximum_payload_bytes = 256 * 1024;

  /// Serializer for successfully inspected filesystem entries.
  static const _entry_codec = FilesystemEntryCodec();

  /// Serializer for typed filesystem inspection issues.
  static const _issue_codec = InspectionIssueCodec();

  /// Stable version 1 wire identifier.
  @override
  String get type_id => 'rudra.filesystem.list.batch.response.v1';

  /// Measures the canonical UTF-8 JSON payload of [message].
  ///
  /// Returns its serialized byte count before communication
  /// envelope encoding and framing.
  ///
  /// The returned size may exceed [maximum_payload_bytes],
  /// allowing producers to evaluate candidate batch boundaries.
  int payload_size(FilesystemListBatchResponse message) {
    return _measure_payload(_encode_payload(message));
  }

  /// Converts [message] into its bounded structured representation.
  ///
  /// Returns the inspection identity, sequence, status and
  /// original filesystem observations.
  ///
  /// Throws [FormatException] when the serialized payload exceeds
  /// the feature's byte ceiling.
  @override
  Map<String, Object?> encode(FilesystemListBatchResponse message) {
    final payload = _encode_payload(message);

    _require_payload_size(payload);

    return payload;
  }

  /// Reconstructs a bounded observation batch from [payload].
  ///
  /// Returns validated immutable filesystem observations.
  ///
  /// Throws [FormatException] for malformed fields, invalid
  /// observation values, contradictory completion status or
  /// exceeded observation and payload limits.
  @override
  FilesystemListBatchResponse decode(Object? payload) {
    final response = _decode(
      payload,
      const {'inspection_id', 'sequence', 'status', 'entries', 'issues'},
      (fields) {
        final entries = fields['entries'];
        final issues = fields['issues'];

        if (entries is! List<Object?> || issues is! List<Object?>) {
          throw const FormatException(
            'Invalid filesystem observation collections.',
          );
        }

        // Validate collection capacity before reconstructing
        // individual filesystem domain objects.
        if (entries.length + issues.length >
            FilesystemListBatchResponse.maximum_observations) {
          throw const FormatException(
            'Filesystem batch exceeds its observation capacity.',
          );
        }

        return FilesystemListBatchResponse(
          inspection_id: _string(fields, 'inspection_id'),
          sequence: _integer(fields, 'sequence'),
          status: FilesystemListBatchStatus.values.byName(
            _string(fields, 'status'),
          ),
          entries: entries.map(_entry_codec.decode).toList(),
          issues: issues.map(_issue_codec.decode).toList(),
        );
      },
    );

    _require_payload_size(_encode_payload(response));

    return response;
  }

  /// Produces the structured representation of [message].
  ///
  /// Returns the payload before byte-capacity validation.
  static Map<String, Object?> _encode_payload(
    FilesystemListBatchResponse message,
  ) {
    return {
      'inspection_id': message.inspection_id,
      'sequence': message.sequence,
      'status': message.status.name,
      'entries': message.entries.map(_entry_codec.encode).toList(),
      'issues': message.issues.map(_issue_codec.encode).toList(),
    };
  }

  /// Returns the canonical UTF-8 JSON byte count of [payload].
  static int _measure_payload(Map<String, Object?> payload) {
    return utf8.encode(jsonEncode(payload)).length;
  }

  /// Validates the serialized byte capacity of [payload].
  ///
  /// Throws [FormatException] when its size exceeds the ceiling.
  static void _require_payload_size(Map<String, Object?> payload) {
    if (_measure_payload(payload) > maximum_payload_bytes) {
      throw const FormatException(
        'Filesystem batch exceeds its serialized payload capacity.',
      );
    }
  }
}

/// Serializes filesystem inspection cancellation requests.
///
/// Example:
/// ```dart
/// const codec = FilesystemListCancelRequestCodec();
/// final payload = codec.encode(request);
/// ```
final class FilesystemListCancelRequestCodec
    implements MessageCodec<FilesystemListCancelRequest> {
  /// Creates the stateless cancellation request codec.
  const FilesystemListCancelRequestCodec();

  /// Stable version 1 wire identifier.
  @override
  String get type_id => 'rudra.filesystem.list.cancel.request.v1';

  /// Returns the inspection identity represented by [message].
  @override
  Map<String, Object?> encode(FilesystemListCancelRequest message) {
    return {'inspection_id': message.inspection_id};
  }

  /// Reconstructs a cancellation request from [payload].
  ///
  /// Throws [FormatException] for invalid fields or identifiers.
  @override
  FilesystemListCancelRequest decode(Object? payload) {
    return _decode(
      payload,
      const {'inspection_id'},
      (fields) => FilesystemListCancelRequest(
        inspection_id: _string(fields, 'inspection_id'),
      ),
    );
  }
}

/// Serializes filesystem inspection retirement confirmations.
///
/// Example:
/// ```dart
/// const codec = FilesystemListCancelResponseCodec();
/// final restored = codec.decode(codec.encode(response));
/// print(restored.inspection_id);
/// ```
final class FilesystemListCancelResponseCodec
    implements MessageCodec<FilesystemListCancelResponse> {
  /// Creates the stateless cancellation response codec.
  const FilesystemListCancelResponseCodec();

  /// Stable version 1 wire identifier.
  @override
  String get type_id => 'rudra.filesystem.list.cancel.response.v1';

  /// Returns the retired inspection identity from [message].
  @override
  Map<String, Object?> encode(FilesystemListCancelResponse message) {
    return {'inspection_id': message.inspection_id};
  }

  /// Reconstructs a cancellation confirmation from [payload].
  ///
  /// Throws [FormatException] for invalid fields or identifiers.
  @override
  FilesystemListCancelResponse decode(Object? payload) {
    return _decode(
      payload,
      const {'inspection_id'},
      (fields) => FilesystemListCancelResponse(
        inspection_id: _string(fields, 'inspection_id'),
      ),
    );
  }
}

/// Validates [payload] and reconstructs its typed representation.
///
/// [expected] identifies the exact permitted field set.
/// [build] reconstructs the validated message.
///
/// Returns the reconstructed value of type [T].
/// Throws [FormatException] for malformed fields or domain values.
T _decode<T>(
  Object? payload,
  Set<String> expected,
  T Function(Map<String, Object?> fields) build,
) {
  if (payload is! Map<String, Object?> ||
      payload.length != expected.length ||
      !expected.every(payload.containsKey)) {
    throw const FormatException('Invalid filesystem list payload.');
  }

  try {
    return build(payload);
  } on ArgumentError {
    throw const FormatException('Invalid filesystem list values.');
  }
}

/// Returns the string identified by [key] in [fields].
///
/// Throws [FormatException] for an incompatible field type.
String _string(Map<String, Object?> fields, String key) {
  final value = fields[key];

  if (value is! String) {
    throw FormatException('Invalid filesystem list field: $key.');
  }

  return value;
}

/// Returns the integer identified by [key] in [fields].
///
/// Throws [FormatException] for an incompatible field type.
int _integer(Map<String, Object?> fields, String key) {
  final value = fields[key];

  if (value is! int) {
    throw FormatException('Invalid filesystem list field: $key.');
  }

  return value;
}
