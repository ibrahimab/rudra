import 'package:rudra_target_contracts/rudra_target_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('FilesystemMetadata', () {
    test('preserves unknown metadata', () {
      final metadata = FilesystemMetadata();

      expect(metadata.logical_size_bytes, isNull);
      expect(metadata.allocated_size_bytes, isNull);
      expect(metadata.created_at, isNull);
      expect(metadata.modified_at, isNull);
      expect(metadata.accessed_at, isNull);
      expect(metadata.identity, isNull);
      expect(metadata.permissions, isNull);
    });

    test('accepts zero-sized entries', () {
      final metadata = FilesystemMetadata(
        logical_size_bytes: 0,
        allocated_size_bytes: 0,
      );

      expect(metadata.logical_size_bytes, 0);
      expect(metadata.allocated_size_bytes, 0);
    });

    test('allows allocated size to exceed logical size', () {
      final metadata = FilesystemMetadata(
        logical_size_bytes: 1,
        allocated_size_bytes: 4096,
      );

      expect(metadata.logical_size_bytes, 1);
      expect(metadata.allocated_size_bytes, 4096);
    });

    test('rejects negative logical size', () {
      expect(
        () => FilesystemMetadata(logical_size_bytes: -1),
        throwsArgumentError,
      );
    });

    test('rejects negative allocated size', () {
      expect(
        () => FilesystemMetadata(allocated_size_bytes: -1),
        throwsArgumentError,
      );
    });

    test('normalizes timestamps to UTC', () {
      final local_time = DateTime(2026, 11, 3, 12, 30);

      final metadata = FilesystemMetadata(
        created_at: local_time,
        modified_at: local_time,
        accessed_at: local_time,
      );

      expect(metadata.created_at!.isUtc, isTrue);
      expect(metadata.modified_at!.isUtc, isTrue);
      expect(metadata.accessed_at!.isUtc, isTrue);

      expect(
        metadata.created_at!.isAtSameMomentAs(local_time),
        isTrue,
      );
    });

    test('retains permission observations', () {
      final permissions = FilesystemPermissions(
        posix_mode: 0x1A4,
      );

      final metadata = FilesystemMetadata(
        permissions: permissions,
      );

      expect(metadata.permissions, same(permissions));
    });

    test('retains filesystem identity observations', () {
      final identity = FilesystemIdentity(
        filesystem_id: 'volume-a',
        entry_id: '123',
      );

      final metadata = FilesystemMetadata(
        identity: identity,
      );

      expect(metadata.identity, same(identity));
    });
  });
}
