import 'package:rudra_target_contracts/rudra_target_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('FilesystemEntry', () {
    test('represents a regular file', () {
      final path = TargetPath('/tmp/example.txt');

      final metadata = FilesystemMetadata(logical_size_bytes: 1024);

      final entry = FilesystemEntry(
        path: path,
        kind: FilesystemEntryKind.regularFile,
        metadata: metadata,
      );

      expect(entry.path, same(path));
      expect(entry.kind, FilesystemEntryKind.regularFile);
      expect(entry.metadata, same(metadata));
    });

    test('represents a directory without recursive size', () {
      final entry = FilesystemEntry(
        path: TargetPath('/tmp/cache'),
        kind: FilesystemEntryKind.directory,
        metadata: FilesystemMetadata(),
      );

      expect(entry.kind, FilesystemEntryKind.directory);
      expect(entry.metadata.logical_size_bytes, isNull);
    });

    test('represents a symbolic link independently', () {
      final entry = FilesystemEntry(
        path: TargetPath('/tmp/cache-link'),
        kind: FilesystemEntryKind.symbolicLink,
        metadata: FilesystemMetadata(),
      );

      expect(entry.kind, FilesystemEntryKind.symbolicLink);
    });

    test('represents special filesystem entries', () {
      final entry = FilesystemEntry(
        path: TargetPath('/tmp/example.sock'),
        kind: FilesystemEntryKind.other,
        metadata: FilesystemMetadata(),
      );

      expect(entry.kind, FilesystemEntryKind.other);
    });

    test('symbolic link retains its own filesystem identity', () {
      final link_identity = FilesystemIdentity(
        filesystem_id: 'volume-a',
        entry_id: 'link-123',
      );

      final entry = FilesystemEntry(
        path: TargetPath('/tmp/cache-link'),
        kind: FilesystemEntryKind.symbolicLink,
        metadata: FilesystemMetadata(identity: link_identity),
      );

      expect(entry.kind, FilesystemEntryKind.symbolicLink);
      expect(entry.metadata.identity, same(link_identity));
    });
  });
}
