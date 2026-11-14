import 'package:rudra_target_contracts/rudra_target_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('TargetInspectionException', () {
    test('preserves typed failure information', () {
      final path = TargetPath('/tmp/private');

      final error = TargetInspectionException(
        code: TargetInspectionErrorCode.permissionDenied,
        operation: TargetInspectionOperation.listDirectory,
        path: path,
        message: 'Directory access denied.',
      );

      expect(error.code, TargetInspectionErrorCode.permissionDenied);

      expect(error.operation, TargetInspectionOperation.listDirectory);

      expect(error.path, same(path));
      expect(error.message, 'Directory access denied.');
    });

    test('implements Exception', () {
      final error = TargetInspectionException(
        code: TargetInspectionErrorCode.notFound,
        operation: TargetInspectionOperation.inspect,
        path: TargetPath('/tmp/missing'),
        message: 'Entry not found.',
      );

      expect(error, isA<Exception>());
    });

    test('preserves an optional underlying cause', () {
      final cause = StateError('Native filesystem failure');

      final error = TargetInspectionException(
        code: TargetInspectionErrorCode.ioFailure,
        operation: TargetInspectionOperation.inspect,
        path: TargetPath('/tmp/file'),
        message: 'Inspection failed.',
        cause: cause,
      );

      expect(error.cause, same(cause));
    });

    test('defaults to no underlying cause', () {
      final error = TargetInspectionException(
        code: TargetInspectionErrorCode.notFound,
        operation: TargetInspectionOperation.inspect,
        path: TargetPath('/tmp/missing'),
        message: 'Entry not found.',
      );

      expect(error.cause, isNull);
    });

    test('rejects empty diagnostic messages', () {
      expect(
        () => TargetInspectionException(
          code: TargetInspectionErrorCode.ioFailure,
          operation: TargetInspectionOperation.inspect,
          path: TargetPath('/tmp/file'),
          message: '',
        ),
        throwsArgumentError,
      );
    });

    test('rejects whitespace-only diagnostic messages', () {
      expect(
        () => TargetInspectionException(
          code: TargetInspectionErrorCode.ioFailure,
          operation: TargetInspectionOperation.inspect,
          path: TargetPath('/tmp/file'),
          message: '   ',
        ),
        throwsArgumentError,
      );
    });

    test('provides diagnostic information in toString', () {
      final error = TargetInspectionException(
        code: TargetInspectionErrorCode.notDirectory,
        operation: TargetInspectionOperation.listDirectory,
        path: TargetPath('/tmp/file.txt'),
        message: 'Expected a directory.',
      );

      final description = error.toString();

      expect(description, contains('notDirectory'));
      expect(description, contains('listDirectory'));
      expect(description, contains('/tmp/file.txt'));
      expect(description, contains('Expected a directory.'));
    });

    test('excludes the underlying cause from toString', () {
      final error = TargetInspectionException(
        code: TargetInspectionErrorCode.ioFailure,
        operation: TargetInspectionOperation.inspect,
        path: TargetPath('/tmp/file'),
        message: 'Inspection failed.',
        cause: StateError('Sensitive native details'),
      );

      expect(error.toString(), isNot(contains('Sensitive native details')));
    });

    test('distinguishes different failure categories', () {
      expect(
        TargetInspectionErrorCode.notFound,
        isNot(TargetInspectionErrorCode.permissionDenied),
      );

      expect(
        TargetInspectionErrorCode.permissionDenied,
        isNot(TargetInspectionErrorCode.ioFailure),
      );
    });
  });
}
