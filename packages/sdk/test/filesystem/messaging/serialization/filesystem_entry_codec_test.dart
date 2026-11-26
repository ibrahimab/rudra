import 'dart:convert';

import 'package:rudra_sdk/src/filesystem/messaging/serialization/filesystem_entry_codec.dart';
import 'package:rudra_target_contracts/rudra_target_contracts.dart';
import 'package:test/test.dart';

/// Verifies filesystem entry serialization across communication
/// boundaries without performing native filesystem inspection.
void main() {
  const codec = FilesystemEntryCodec();

  final created_at = DateTime.utc(2026, 11, 26, 1, 2, 3, 456, 789);

  final modified_at = DateTime.utc(2026, 11, 26, 4, 5, 6);

  final entry = FilesystemEntry(
    path: TargetPath(r'C:\Users\example\file.txt'),
    kind: FilesystemEntryKind.regularFile,
    metadata: FilesystemMetadata(
      logical_size_bytes: 5368709120,
      allocated_size_bytes: 5368713216,
      created_at: created_at,
      modified_at: modified_at,
      identity: FilesystemIdentity(
        filesystem_id: 'volume-001',
        entry_id: 'entry-001',
      ),
      permissions: FilesystemPermissions(
        posix_mode: 0x1A4,
        effective_readable: true,
        effective_writable: false,
      ),
    ),
  );

  group('FilesystemEntryCodec', () {
    test('preserves the structured observation representation', () {
      expect(codec.encode(entry), {
        'path': r'C:\Users\example\file.txt',
        'kind': 'regularFile',
        'metadata': {
          'logical_size_bytes': 5368709120,
          'allocated_size_bytes': 5368713216,
          'created_at': '2026-11-26T01:02:03.456789Z',
          'modified_at': '2026-11-26T04:05:06.000Z',
          'accessed_at': null,
          'identity': {'filesystem_id': 'volume-001', 'entry_id': 'entry-001'},
          'permissions': {
            'posix_mode': 0x1A4,
            'effective_readable': true,
            'effective_writable': false,
            'effective_executable': null,
          },
        },
      });
    });

    test('round-trips observed metadata through JSON', () {
      final payload = codec.encode(entry);

      final restored = codec.decode(jsonDecode(jsonEncode(payload)));

      expect(restored.path.value, entry.path.value);
      expect(restored.kind, entry.kind);

      final metadata = restored.metadata;

      expect(metadata.logical_size_bytes, 5368709120);
      expect(metadata.allocated_size_bytes, 5368713216);
      expect(metadata.created_at, created_at);
      expect(metadata.created_at!.isUtc, isTrue);
      expect(metadata.created_at!.microsecond, 789);
      expect(metadata.modified_at, modified_at);
      expect(metadata.accessed_at, isNull);

      expect(metadata.identity, entry.metadata.identity);

      final permissions = metadata.permissions!;

      expect(permissions.posix_mode, 0x1A4);
      expect(permissions.effective_readable, isTrue);
      expect(permissions.effective_writable, isFalse);
      expect(permissions.effective_executable, isNull);

      expect(codec.encode(restored), payload);
    });

    test('preserves completely unavailable metadata', () {
      final original = FilesystemEntry(
        path: TargetPath('/workspace/unknown'),
        kind: FilesystemEntryKind.other,
        metadata: FilesystemMetadata(),
      );

      final payload = codec.encode(original);

      expect(payload['metadata'], {
        'logical_size_bytes': null,
        'allocated_size_bytes': null,
        'created_at': null,
        'modified_at': null,
        'accessed_at': null,
        'identity': null,
        'permissions': null,
      });

      final restored = codec.decode(jsonDecode(jsonEncode(payload)));

      expect(restored.metadata.logical_size_bytes, isNull);
      expect(restored.metadata.allocated_size_bytes, isNull);
      expect(restored.metadata.created_at, isNull);
      expect(restored.metadata.modified_at, isNull);
      expect(restored.metadata.accessed_at, isNull);
      expect(restored.metadata.identity, isNull);
      expect(restored.metadata.permissions, isNull);
    });

    test('distinguishes zero values and unavailable observations', () {
      final original = FilesystemEntry(
        path: TargetPath('/workspace/empty'),
        kind: FilesystemEntryKind.regularFile,
        metadata: FilesystemMetadata(
          logical_size_bytes: 0,
          allocated_size_bytes: 0,
          permissions: FilesystemPermissions(
            posix_mode: 0,
            effective_readable: false,
            effective_writable: false,
            effective_executable: false,
          ),
        ),
      );

      final restored = codec.decode(
        jsonDecode(jsonEncode(codec.encode(original))),
      );

      expect(restored.metadata.logical_size_bytes, 0);
      expect(restored.metadata.allocated_size_bytes, 0);

      final permissions = restored.metadata.permissions!;

      expect(permissions.posix_mode, 0);
      expect(permissions.effective_readable, isFalse);
      expect(permissions.effective_writable, isFalse);
      expect(permissions.effective_executable, isFalse);
    });

    test('preserves target-native paths and every entry kind', () {
      final paths = [
        '/workspace/file.txt',
        '/workspace/../example',
        '/workspace/日本語',
        r'C:\Users\example\Downloads',
        r'\\server\share\directory',
        '/workspace/ file with spaces ',
      ];

      for (final path in paths) {
        for (final kind in FilesystemEntryKind.values) {
          final original = FilesystemEntry(
            path: TargetPath(path),
            kind: kind,
            metadata: FilesystemMetadata(),
          );

          final restored = codec.decode(
            jsonDecode(jsonEncode(codec.encode(original))),
          );

          expect(restored.path.value, path);
          expect(restored.kind, kind);
        }
      }
    });

    test('rejects malformed entry representations', () {
      final payload = codec.encode(entry);

      final invalid_payloads = <Object?>[
        null,
        [],
        'entry',
        <String, Object?>{},
        {...payload, 'path': null},
        {...payload, 'path': ''},
        {...payload, 'path': '/workspace\u0000'},
        {...payload, 'kind': 0},
        {...payload, 'kind': 'unsupported'},
        {...payload, 'metadata': null},
        {...payload, 'unexpected': true},
        {...payload}..remove('metadata'),
      ];

      for (final invalid in invalid_payloads) {
        expect(
          () => codec.decode(invalid),
          throwsFormatException,
          reason: 'Invalid entry representation: $invalid',
        );
      }
    });

    test('rejects malformed metadata representations', () {
      final payload = codec.encode(entry);

      final metadata = payload['metadata'] as Map<String, Object?>;

      final invalid_metadata = <Object?>[
        null,
        [],
        {...metadata, 'logical_size_bytes': -1},
        {...metadata, 'logical_size_bytes': '1024'},
        {...metadata, 'logical_size_bytes': 1.5},
        {...metadata, 'allocated_size_bytes': -1},
        {...metadata, 'allocated_size_bytes': true},
        {...metadata, 'created_at': 0},
        {...metadata, 'created_at': 'invalid'},
        {...metadata, 'created_at': '2026-02-30T00:00:00.000Z'},
        {...metadata, 'created_at': '2026-11-26T00:00:00'},
        {...metadata, 'created_at': '2026-11-26T00:00:00.1234567Z'},
        {...metadata, 'unexpected': null},
        {...metadata}..remove('accessed_at'),
      ];

      for (final invalid in invalid_metadata) {
        expect(
          () => codec.decode({...payload, 'metadata': invalid}),
          throwsFormatException,
          reason: 'Invalid metadata representation: $invalid',
        );
      }
    });

    test('rejects malformed filesystem identities', () {
      final payload = codec.encode(entry);

      final metadata = payload['metadata'] as Map<String, Object?>;

      final invalid_identities = <Object?>[
        [],
        {},
        {'filesystem_id': '', 'entry_id': 'entry-001'},
        {'filesystem_id': 'volume-001', 'entry_id': ' '},
        {'filesystem_id': 42, 'entry_id': 'entry-001'},
        {
          'filesystem_id': 'volume-001',
          'entry_id': 'entry-001',
          'unexpected': true,
        },
      ];

      for (final identity in invalid_identities) {
        expect(
          () => codec.decode({
            ...payload,
            'metadata': {...metadata, 'identity': identity},
          }),
          throwsFormatException,
        );
      }
    });

    test('rejects malformed permission observations', () {
      final payload = codec.encode(entry);

      final metadata = payload['metadata'] as Map<String, Object?>;

      final permissions = metadata['permissions'] as Map<String, Object?>;

      final invalid_permissions = <Object?>[
        [],
        {},
        {...permissions, 'posix_mode': -1},
        {...permissions, 'posix_mode': 0x1000},
        {...permissions, 'posix_mode': '0644'},
        {...permissions, 'effective_readable': 1},
        {...permissions, 'effective_writable': 'false'},
        {...permissions, 'effective_executable': 0},
        {...permissions, 'unexpected': null},
        {...permissions}..remove('effective_executable'),
      ];

      for (final invalid in invalid_permissions) {
        expect(
          () => codec.decode({
            ...payload,
            'metadata': {...metadata, 'permissions': invalid},
          }),
          throwsFormatException,
        );
      }
    });
  });
}
