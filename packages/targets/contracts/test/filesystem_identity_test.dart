import 'package:rudra_target_contracts/rudra_target_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('FilesystemIdentity', () {
    test('equal components produce equal identities', () {
      final first = FilesystemIdentity(
        filesystem_id: 'volume-a',
        entry_id: '123',
      );

      final second = FilesystemIdentity(
        filesystem_id: 'volume-a',
        entry_id: '123',
      );

      expect(first, equals(second));
      expect(first.hashCode, second.hashCode);

      final identities = <FilesystemIdentity>{first, second};

      expect(identities, hasLength(1));
    });

    test('different filesystems produce different identities', () {
      final first = FilesystemIdentity(
        filesystem_id: 'volume-a',
        entry_id: '123',
      );

      final second = FilesystemIdentity(
        filesystem_id: 'volume-b',
        entry_id: '123',
      );

      expect(first, isNot(equals(second)));
    });

    test('different entry identifiers are not equal', () {
      final first = FilesystemIdentity(
        filesystem_id: 'volume-a',
        entry_id: '123',
      );

      final second = FilesystemIdentity(
        filesystem_id: 'volume-a',
        entry_id: '456',
      );

      expect(first, isNot(equals(second)));
    });

    test('rejects blank filesystem identifiers', () {
      expect(
        () => FilesystemIdentity(filesystem_id: '  ', entry_id: '123'),
        throwsArgumentError,
      );
    });

    test('rejects blank entry identifiers', () {
      expect(
        () => FilesystemIdentity(filesystem_id: 'volume-a', entry_id: ''),
        throwsArgumentError,
      );
    });

    test('preserves opaque identifier strings', () {
      final identity = FilesystemIdentity(
        filesystem_id: 'device:123',
        entry_id: 'object/456',
      );

      expect(identity.filesystem_id, 'device:123');
      expect(identity.entry_id, 'object/456');
    });
  });
}
