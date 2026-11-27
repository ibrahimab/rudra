import 'dart:convert';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import 'package:rudra_sdk/src/filesystem/messaging/filesystem_messaging_module.dart';
import 'package:rudra_sdk/src/filesystem/messaging/list/codecs/filesystem_list_codecs.dart';
import 'package:rudra_sdk/src/filesystem/messaging/list/filesystem_list_messages.dart';
import 'package:rudra_sdk/src/filesystem/messaging/serialization/inspection_issue_codec.dart';

import 'package:test/test.dart';

/// Verifies bounded filesystem messaging and feature composition.
void main() {
  const inspection_id = 'inspection-001';
  const target_id = 'local-macos';

  const batch_codec = FilesystemListBatchResponseCodec();
  const issue_codec = InspectionIssueCodec();

  final directory = TargetPath('/workspace');

  final entry = FilesystemEntry(
    path: TargetPath('/workspace/example.txt'),
    kind: FilesystemEntryKind.regularFile,
    metadata: FilesystemMetadata(
      logical_size_bytes: 1024,
      allocated_size_bytes: 4096,
    ),
  );

  final issue = InspectionIssue(
    code: TargetInspectionErrorCode.permissionDenied,
    operation: TargetInspectionOperation.inspect,
    path: TargetPath('/workspace/restricted'),
    message: 'Permission denied.',
  );

  group('Feature composition', () {
    test('contributes codecs without freezing the registry', () {
      const module = FilesystemMessagingModule();

      final registry = MessageCodecRegistry();

      expect(module.module_id, 'rudra.filesystem.messaging');

      module.register_codecs(registry);

      expect(registry.is_frozen, isFalse);

      registry.freeze();

      expect(
        registry.response_type_for(
          FilesystemListOpenRequest(
            inspection_id: inspection_id,

            directory: directory,
          ),
        ),
        FilesystemListOpenResponse,
      );

      expect(
        registry.response_type_for(
          FilesystemListNextRequest(inspection_id: inspection_id, sequence: 1),
        ),
        FilesystemListBatchResponse,
      );

      expect(
        registry.response_type_for(
          FilesystemListCancelRequest(inspection_id: inspection_id),
        ),
        FilesystemListCancelResponse,
      );
    });

    test('round-trips all messages through independent registries', () {
      final host = create_application_message_codecs();
      final client = create_application_message_codecs();

      final messages = <Message>[
        FilesystemListOpenRequest(
          inspection_id: inspection_id,

          directory: directory,
        ),
        FilesystemListOpenResponse(
          inspection_id: inspection_id,
          target_id: target_id,
        ),
        FilesystemListNextRequest(inspection_id: inspection_id, sequence: 1),
        FilesystemListBatchResponse(
          inspection_id: inspection_id,
          sequence: 1,
          status: FilesystemListBatchStatus.more,
          entries: [entry],
          issues: [issue],
        ),
        FilesystemListCancelRequest(inspection_id: inspection_id),
        FilesystemListCancelResponse(inspection_id: inspection_id),
      ];

      for (final message in messages) {
        final encoded = host.encode(message);

        final restored = client.decode(
          encoded.type_id,
          jsonDecode(jsonEncode(encoded.payload)),
        );

        expect(restored.runtimeType, message.runtimeType);

        final reconstructed = client.encode(restored);

        expect(reconstructed.type_id, encoded.type_id);
        expect(reconstructed.payload, encoded.payload);
      }
    });
  });

  group('Inspection admission', () {
    const codec = FilesystemListOpenRequestCodec();

    test('preserves target-native paths and returns the host target', () {
      final paths = [
        '/workspace',
        '/workspace/../example',
        '/workspace/日本語',
        r'C:\Users\example\Downloads',
        r'\\server\share\directory',
      ];

      for (final path in paths) {
        final request = FilesystemListOpenRequest(
          inspection_id: inspection_id,

          directory: TargetPath(path),
        );

        final restored = codec.decode(
          jsonDecode(jsonEncode(codec.encode(request))),
        );

        expect(restored.inspection_id, inspection_id);
        expect(restored.directory.value, path);
      }
    });

    test('requires an authoritative target on the admission response', () {
      const response_codec = FilesystemListOpenResponseCodec();
      final admission = FilesystemListOpenResponse(
        inspection_id: inspection_id,
        target_id: ' Target-001 ',
      );
      expect(
        response_codec.decode(response_codec.encode(admission)).target_id,
        ' Target-001 ',
      );
      expect(
        () => response_codec.decode({'inspection_id': inspection_id}),
        throwsFormatException,
      );
      expect(
        () => response_codec.decode({
          'inspection_id': inspection_id,
          'target_id': ' ',
        }),
        throwsFormatException,
      );
    });

    test('rejects invalid inspection identifiers', () {
      final identifiers = [
        '',
        ' ',
        'inspection 1',
        'inspection/1',
        'inspection\n',
        '日本語',
        List.filled(65, 'a').join(),
      ];

      for (final identifier in identifiers) {
        expect(
          () => FilesystemListOpenRequest(
            inspection_id: identifier,

            directory: directory,
          ),
          throwsArgumentError,
        );
      }
    });

    test('rejects untrusted infrastructure parameters', () {
      final payload = codec.encode(
        FilesystemListOpenRequest(
          inspection_id: inspection_id,

          directory: directory,
        ),
      );

      final invalid_payloads = <Object?>[
        {...payload, 'os_user_id': 'untrusted-user'},
        {...payload, 'scope_directory': '/untrusted'},
        {...payload, 'scope_id': 'untrusted-scope'},
        {...payload, 'target_id': 'untrusted-target'},
        {...payload, 'directory': ''},
        {...payload, 'directory': '/workspace\u0000'},
        {...payload, 'directory': 42},
        {...payload}..remove('directory'),
      ];

      for (final invalid in invalid_payloads) {
        expect(() => codec.decode(invalid), throwsFormatException);
      }
    });
  });

  group('Observation batches', () {
    test('preserves successful and unsuccessful observations', () {
      final response = FilesystemListBatchResponse(
        inspection_id: inspection_id,
        sequence: 7,
        status: FilesystemListBatchStatus.more,
        entries: [entry],
        issues: [issue],
      );

      final restored = batch_codec.decode(
        jsonDecode(jsonEncode(batch_codec.encode(response))),
      );

      expect(restored.inspection_id, inspection_id);
      expect(restored.sequence, 7);
      expect(restored.status, FilesystemListBatchStatus.more);
      expect(restored.status.is_terminal, isFalse);
      expect(restored.observation_count, 2);

      expect(restored.entries.single.path.value, entry.path.value);

      expect(restored.entries.single.metadata.logical_size_bytes, 1024);

      expect(restored.issues.single.code, issue.code);
      expect(restored.issues.single.operation, issue.operation);
      expect(restored.issues.single.path.value, issue.path.value);
      expect(restored.issues.single.message, issue.message);
    });

    test('preserves ordering within observation collections', () {
      final second_entry = FilesystemEntry(
        path: TargetPath('/workspace/another.txt'),
        kind: FilesystemEntryKind.regularFile,
        metadata: FilesystemMetadata(),
      );

      final second_issue = InspectionIssue(
        code: TargetInspectionErrorCode.ioFailure,
        operation: TargetInspectionOperation.listDirectory,
        path: directory,
        message: 'Enumeration failed.',
      );

      final response = FilesystemListBatchResponse(
        inspection_id: inspection_id,
        sequence: 1,
        status: FilesystemListBatchStatus.incomplete,
        entries: [entry, second_entry],
        issues: [issue, second_issue],
      );

      final restored = batch_codec.decode(
        jsonDecode(jsonEncode(batch_codec.encode(response))),
      );

      expect(restored.entries.map((entry) => entry.path.value), [
        entry.path.value,
        second_entry.path.value,
      ]);

      expect(restored.issues.map((issue) => issue.code), [
        issue.code,
        second_issue.code,
      ]);
    });

    test('represents an empty completed directory', () {
      final response = FilesystemListBatchResponse(
        inspection_id: inspection_id,
        sequence: 1,
        status: FilesystemListBatchStatus.complete,
        entries: [],
        issues: [],
      );

      final restored = batch_codec.decode(
        jsonDecode(jsonEncode(batch_codec.encode(response))),
      );

      expect(restored.status, FilesystemListBatchStatus.complete);
      expect(restored.status.is_terminal, isTrue);
      expect(restored.observation_count, 0);
    });

    test('allows terminal incomplete status after earlier issues', () {
      final response = FilesystemListBatchResponse(
        inspection_id: inspection_id,
        sequence: 3,
        status: FilesystemListBatchStatus.incomplete,
        entries: [],
        issues: [],
      );

      final restored = batch_codec.decode(
        jsonDecode(jsonEncode(batch_codec.encode(response))),
      );

      expect(restored.status, FilesystemListBatchStatus.incomplete);
      expect(restored.status.is_terminal, isTrue);
      expect(restored.issues, isEmpty);
    });

    test('rejects contradictory batch contents', () {
      expect(
        () => FilesystemListBatchResponse(
          inspection_id: inspection_id,
          sequence: 1,
          status: FilesystemListBatchStatus.more,
          entries: [],
          issues: [],
        ),
        throwsArgumentError,
      );

      expect(
        () => FilesystemListBatchResponse(
          inspection_id: inspection_id,
          sequence: 1,
          status: FilesystemListBatchStatus.complete,
          entries: [entry],
          issues: [issue],
        ),
        throwsArgumentError,
      );
    });

    test('defensively copies observation collections', () {
      final entries = [entry];
      final issues = [issue];

      final response = FilesystemListBatchResponse(
        inspection_id: inspection_id,
        sequence: 1,
        status: FilesystemListBatchStatus.incomplete,
        entries: entries,
        issues: issues,
      );

      entries.clear();
      issues.clear();

      expect(response.entries, [entry]);
      expect(response.issues, [issue]);

      expect(() => response.entries.clear(), throwsUnsupportedError);

      expect(() => response.issues.clear(), throwsUnsupportedError);
    });
  });

  group('Bounded payloads', () {
    test('accepts the maximum combined observation count', () {
      const capacity = FilesystemListBatchResponse.maximum_observations;

      final response = FilesystemListBatchResponse(
        inspection_id: inspection_id,
        sequence: 1,
        status: FilesystemListBatchStatus.more,
        entries: List.filled(capacity - 1, entry),
        issues: [issue],
      );

      final restored = batch_codec.decode(
        jsonDecode(jsonEncode(batch_codec.encode(response))),
      );

      expect(restored.observation_count, capacity);
    });

    test('rejects batches exceeding observation capacity', () {
      const capacity = FilesystemListBatchResponse.maximum_observations;

      expect(
        () => FilesystemListBatchResponse(
          inspection_id: inspection_id,
          sequence: 1,
          status: FilesystemListBatchStatus.more,
          entries: List.filled(capacity, entry),
          issues: [issue],
        ),
        throwsArgumentError,
      );

      final valid = batch_codec.encode(
        FilesystemListBatchResponse(
          inspection_id: inspection_id,
          sequence: 1,
          status: FilesystemListBatchStatus.more,
          entries: List.filled(capacity, entry),
          issues: [],
        ),
      );

      expect(
        () => batch_codec.decode({
          ...valid,
          'issues': [issue_codec.encode(issue)],
        }),
        throwsFormatException,
      );
    });

    test('measures serialized UTF-8 bytes rather than characters', () {
      final unicode_issue = InspectionIssue(
        code: TargetInspectionErrorCode.ioFailure,
        operation: TargetInspectionOperation.inspect,
        path: TargetPath('/workspace/日本語'),
        message: '観測できませんでした。',
      );

      final response = FilesystemListBatchResponse(
        inspection_id: inspection_id,
        sequence: 1,
        status: FilesystemListBatchStatus.incomplete,
        entries: [],
        issues: [unicode_issue],
      );

      final json = jsonEncode(batch_codec.encode(response));

      expect(batch_codec.payload_size(response), utf8.encode(json).length);

      expect(batch_codec.payload_size(response), greaterThan(json.length));
    });

    test('enforces the exact serialized payload boundary', () {
      const capacity = FilesystemListBatchResponseCodec.maximum_payload_bytes;

      FilesystemListBatchResponse create_response(String message) {
        return FilesystemListBatchResponse(
          inspection_id: inspection_id,
          sequence: 1,
          status: FilesystemListBatchStatus.incomplete,
          entries: [],
          issues: [
            InspectionIssue(
              code: issue.code,
              operation: issue.operation,
              path: issue.path,
              message: message,
            ),
          ],
        );
      }

      final minimum = create_response('x');

      final remaining = capacity - batch_codec.payload_size(minimum);

      // Each additional ASCII character contributes exactly one
      // byte to the canonical JSON payload.
      final boundary_message = List.filled(remaining + 1, 'x').join();

      final boundary = create_response(boundary_message);

      expect(batch_codec.payload_size(boundary), capacity);

      final payload = batch_codec.encode(boundary);

      expect(
        batch_codec
            .decode(jsonDecode(jsonEncode(payload)))
            .issues
            .single
            .message,
        boundary_message,
      );

      final oversized = create_response('${boundary_message}x');

      expect(batch_codec.payload_size(oversized), capacity + 1);

      expect(() => batch_codec.encode(oversized), throwsFormatException);

      expect(
        () => batch_codec.decode({
          ...payload,
          'issues': [
            {...issue_codec.encode(issue), 'message': '${boundary_message}x'},
          ],
        }),
        throwsFormatException,
      );
    });

    test('rejects oversized multibyte observations', () {
      const capacity = FilesystemListBatchResponseCodec.maximum_payload_bytes;

      final message = List.filled(capacity ~/ 2, '界').join();

      final oversized_issue = InspectionIssue(
        code: issue.code,
        operation: issue.operation,
        path: issue.path,
        message: message,
      );

      final response = FilesystemListBatchResponse(
        inspection_id: inspection_id,
        sequence: 1,
        status: FilesystemListBatchStatus.incomplete,
        entries: [],
        issues: [oversized_issue],
      );

      expect(message.length, lessThan(capacity));

      expect(batch_codec.payload_size(response), greaterThan(capacity));

      expect(() => batch_codec.encode(response), throwsFormatException);
    });

    test('standard communication leaves batch envelope headroom', () {
      const options = MessageSessionOptions();

      expect(
        FilesystemListBatchResponseCodec.maximum_payload_bytes,
        lessThan(options.maximum_frame_size),
      );
    });
  });

  group('Malformed messaging', () {
    test('rejects invalid batch sequence values', () {
      for (final sequence in [0, -1]) {
        expect(
          () => FilesystemListNextRequest(
            inspection_id: inspection_id,
            sequence: sequence,
          ),
          throwsArgumentError,
        );

        expect(
          () => FilesystemListBatchResponse(
            inspection_id: inspection_id,
            sequence: sequence,
            status: FilesystemListBatchStatus.complete,
            entries: [],
            issues: [],
          ),
          throwsArgumentError,
        );
      }
    });

    test('rejects malformed registered message representations', () {
      final registry = create_application_message_codecs();

      final batch = batch_codec.encode(
        FilesystemListBatchResponse(
          inspection_id: inspection_id,
          sequence: 1,
          status: FilesystemListBatchStatus.more,
          entries: [entry],
          issues: [issue],
        ),
      );

      final cases = <(String, Object?)>[
        (
          'rudra.filesystem.list.open.request.v2',
          {'inspection_id': inspection_id, 'target_id': target_id},
        ),
        ('rudra.filesystem.list.open.response.v2', {'inspection_id': ''}),
        (
          'rudra.filesystem.list.next.request.v1',
          {'inspection_id': inspection_id, 'sequence': '1'},
        ),
        (
          'rudra.filesystem.list.next.request.v1',
          {'inspection_id': inspection_id, 'sequence': 0},
        ),
        (
          'rudra.filesystem.list.batch.response.v1',
          {...batch, 'status': 'unknown'},
        ),
        (
          'rudra.filesystem.list.batch.response.v1',
          {...batch, 'status': 'complete'},
        ),
        ('rudra.filesystem.list.batch.response.v1', {...batch, 'sequence': -1}),
        (
          'rudra.filesystem.list.batch.response.v1',
          {...batch, 'entries': null},
        ),
        (
          'rudra.filesystem.list.batch.response.v1',
          {
            ...batch,
            'entries': [null],
          },
        ),
        (
          'rudra.filesystem.list.batch.response.v1',
          {
            ...batch,
            'issues': [null],
          },
        ),
        (
          'rudra.filesystem.list.batch.response.v1',
          {...batch, 'entries': [], 'issues': []},
        ),
        (
          'rudra.filesystem.list.batch.response.v1',
          {...batch, 'unexpected': true},
        ),
        (
          'rudra.filesystem.list.batch.response.v1',
          {...batch}..remove('issues'),
        ),
        ('rudra.filesystem.list.cancel.request.v1', {'inspection_id': 1}),
        ('rudra.filesystem.list.cancel.response.v1', {}),
      ];

      for (final (type_id, payload) in cases) {
        expect(
          () => registry.decode(type_id, payload),
          throwsFormatException,
          reason: type_id,
        );
      }
    });
  });
}
