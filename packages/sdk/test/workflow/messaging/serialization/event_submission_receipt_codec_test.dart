import 'dart:convert';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_sdk/src/workflow/messaging/serialization/event_submission_receipt_codec.dart';
import 'package:test/test.dart';

/// Verifies structured serialization of durable submission receipts.
void main() {
  const codec = EventSubmissionReceiptCodec();

  test('preserves event and correlation identities', () {
    final receipt = EventSubmissionReceipt(
      event_id: 'event-001',
      correlation_id: 'correlation-001',
    );

    final payload = codec.encode(receipt);

    expect(payload, {
      'event_id': 'event-001',
      'correlation_id': 'correlation-001',
    });

    final restored = codec.decode(jsonDecode(jsonEncode(payload)));

    expect(restored.event_id, receipt.event_id);
    expect(restored.correlation_id, receipt.correlation_id);
  });

  test('preserves identifier spelling without normalization', () {
    final receipt = EventSubmissionReceipt(
      event_id: ' Event-001 ',
      correlation_id: ' Correlation-001 ',
    );

    final restored = codec.decode(codec.encode(receipt));

    expect(restored.event_id, receipt.event_id);
    expect(restored.correlation_id, receipt.correlation_id);
  });

  test('rejects malformed receipt representations', () {
    final invalid_payloads = <Object?>[
      null,
      'event-001',
      [],
      <String, Object?>{},
      {'event_id': 'event-001'},
      {'event_id': 42, 'correlation_id': 'correlation-001'},
      {'event_id': 'event-001', 'correlation_id': null},
      {
        'event_id': 'event-001',
        'correlation_id': 'correlation-001',
        'unexpected': true,
      },
      {'event_id': 'event-001', 'scope_id': 'untrusted-scope'},
    ];

    for (final payload in invalid_payloads) {
      expect(
        () => codec.decode(payload),
        throwsA(isA<FormatException>()),
        reason: 'Invalid receipt payload: $payload',
      );
    }
  });

  test('rejects blank submission identifiers', () {
    final invalid_identifiers = ['', ' ', '\t\n'];

    for (final identifier in invalid_identifiers) {
      expect(
        () => codec.decode({
          'event_id': identifier,
          'correlation_id': 'correlation-001',
        }),
        throwsA(isA<FormatException>()),
      );

      expect(
        () => codec.decode({
          'event_id': 'event-001',
          'correlation_id': identifier,
        }),
        throwsA(isA<FormatException>()),
      );
    }
  });
}
