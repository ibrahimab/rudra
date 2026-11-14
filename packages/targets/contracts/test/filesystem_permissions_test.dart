import 'package:rudra_target_contracts/rudra_target_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('FilesystemPermissions', () {
    test('preserves POSIX permission bits', () {
      final permissions = FilesystemPermissions(posix_mode: 0x1A4);

      expect(permissions.posix_mode, 420);
    });

    test('accepts the full valid POSIX bit range', () {
      final permissions = FilesystemPermissions(posix_mode: 0x0FFF);

      expect(permissions.posix_mode, 0x0FFF);
    });

    test('rejects negative permission bits', () {
      expect(() => FilesystemPermissions(posix_mode: -1), throwsRangeError);
    });

    test('rejects POSIX file-type bits', () {
      expect(() => FilesystemPermissions(posix_mode: 0x1000), throwsRangeError);
    });

    test('preserves unknown effective access', () {
      final permissions = FilesystemPermissions();

      expect(permissions.posix_mode, isNull);
      expect(permissions.effective_readable, isNull);
      expect(permissions.effective_writable, isNull);
      expect(permissions.effective_executable, isNull);
    });

    test('distinguishes denied access from unknown access', () {
      final permissions = FilesystemPermissions(
        effective_readable: true,
        effective_writable: false,
      );

      expect(permissions.effective_readable, isTrue);
      expect(permissions.effective_writable, isFalse);
      expect(permissions.effective_executable, isNull);
    });
  });
}
