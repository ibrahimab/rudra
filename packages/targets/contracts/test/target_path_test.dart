import 'package:rudra_target_contracts/rudra_target_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('TargetPath', () {
    test('preserves macOS paths without modification', () {
      final path = TargetPath(
        '/Users/example/Library/Caches',
      );

      expect(
        path.value,
        '/Users/example/Library/Caches',
      );
    });

    test('preserves Windows path separators', () {
      final path = TargetPath(
        r'C:\Users\example\AppData',
      );

      expect(
        path.value,
        r'C:\Users\example\AppData',
      );
    });

    test('preserves relative path components', () {
      final path = TargetPath(
        '../cache/./downloads',
      );

      expect(
        path.value,
        '../cache/./downloads',
      );
    });

    test('preserves whitespace without trimming', () {
      final path = TargetPath(' cache ');

      expect(path.value, ' cache ');
    });

    test('rejects an empty path', () {
      expect(
        () => TargetPath(''),
        throwsArgumentError,
      );
    });

    test('rejects embedded NUL characters', () {
      expect(
        () => TargetPath('cache\u0000files'),
        throwsArgumentError,
      );
    });
  });
}
