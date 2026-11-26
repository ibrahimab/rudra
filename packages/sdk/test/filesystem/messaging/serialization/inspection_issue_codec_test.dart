import 'dart:convert';

import 'package:rudra_sdk/src/filesystem/inspection_issue.dart';
import 'package:rudra_sdk/src/filesystem/messaging/serialization/inspection_issue_codec.dart';
import 'package:rudra_target_contracts/rudra_target_contracts.dart';
import 'package:test/test.dart';

/// Verifies typed filesystem inspection failure representations.
void main() {
  const codec = InspectionIssueCodec();

  final issue = InspectionIssue(
    code: TargetInspectionErrorCode.permissionDenied,
    operation: TargetInspectionOperation.inspect,
    path: TargetPath('/workspace/restricted'),
    message: 'Permission denied.',
  );

  group('InspectionIssueCodec', () {
    test('preserves the structured inspection issue representation', () {
      expect(codec.encode(issue), {
        'code': 'permissionDenied',
        'operation': 'inspect',
        'path': '/workspace/restricted',
        'message': 'Permission denied.',
      });
    });

    test('round-trips every inspection classification and operation', () {
      for (final code in TargetInspectionErrorCode.values) {
        for (final operation in TargetInspectionOperation.values) {
          final original = InspectionIssue(
            code: code,
            operation: operation,
            path: TargetPath('/workspace/example'),
            message: 'Observed inspection failure.',
          );

          final payload = codec.encode(original);

          final restored = codec.decode(jsonDecode(jsonEncode(payload)));

          expect(restored.code, code);
          expect(restored.operation, operation);
          expect(restored.path.value, original.path.value);
          expect(restored.message, original.message);

          expect(codec.encode(restored), payload);
        }
      }
    });

    test('preserves target-native paths and diagnostic messages', () {
      final paths = [
        '/workspace/restricted',
        r'C:\Users\example\restricted',
        r'\\server\share\restricted',
        '/workspace/../restricted',
        '/workspace/日本語',
      ];

      for (final path in paths) {
        final original = InspectionIssue(
          code: TargetInspectionErrorCode.ioFailure,
          operation: TargetInspectionOperation.listDirectory,
          path: TargetPath(path),
          message: ' Inspection failed.\nAdditional information. ',
        );

        final restored = codec.decode(
          jsonDecode(jsonEncode(codec.encode(original))),
        );

        expect(restored.path.value, path);
        expect(restored.message, original.message);
      }
    });

    test('excludes native exception causes from the representation', () {
      final exception = TargetInspectionException(
        code: TargetInspectionErrorCode.ioFailure,
        operation: TargetInspectionOperation.inspect,
        path: TargetPath('/workspace/example'),
        message: 'Unable to inspect entry.',
        cause: StateError('Native implementation diagnostic.'),
      );

      final original = InspectionIssue.from_target_exception(exception);

      final payload = codec.encode(original);

      expect(payload, {
        'code': 'ioFailure',
        'operation': 'inspect',
        'path': '/workspace/example',
        'message': 'Unable to inspect entry.',
      });

      final restored = codec.decode(jsonDecode(jsonEncode(payload)));

      expect(restored.message, exception.message);
    });

    test('rejects malformed inspection issue representations', () {
      final payload = codec.encode(issue);

      final invalid_payloads = <Object?>[
        null,
        [],
        'issue',
        <String, Object?>{},
        {...payload, 'code': 'unsupported'},
        {...payload, 'code': 0},
        {...payload, 'operation': 'unsupported'},
        {...payload, 'operation': null},
        {...payload, 'path': ''},
        {...payload, 'path': '/workspace\u0000'},
        {...payload, 'path': 42},
        {...payload, 'message': ''},
        {...payload, 'message': ' \t\n'},
        {...payload, 'message': null},
        {...payload, 'cause': 'Native diagnostic'},
        {...payload, 'unexpected': true},
        {...payload}..remove('message'),
      ];

      for (final invalid in invalid_payloads) {
        expect(
          () => codec.decode(invalid),
          throwsFormatException,
          reason: 'Invalid inspection issue representation: $invalid',
        );
      }
    });
  });
}
