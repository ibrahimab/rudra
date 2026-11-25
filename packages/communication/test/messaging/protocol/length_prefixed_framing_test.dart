import 'dart:async';
import 'dart:typed_data';

import 'package:rudra_communication/src/messaging/protocol/length_prefixed_framing.dart';
import 'package:rudra_communication/src/messaging/protocol/protocol_exception.dart';
import 'package:test/test.dart';

/// Verifies frame boundaries, incremental assembly, resource limits
/// and incoming stream lifecycle behavior.
void main() {
  final invalid_length = isA<ProtocolException>().having(
    (error) => error.code,
    'code',
    ProtocolErrorCode.invalid_frame_length,
  );

  final incomplete_frame = isA<ProtocolException>().having(
    (error) => error.code,
    'code',
    ProtocolErrorCode.incomplete_frame,
  );

  group('configuration and encoding', () {
    test('provides a bounded default frame size', () {
      final framing = LengthPrefixedFraming();

      expect(framing.maximum_frame_size, 1024 * 1024);
    });

    test('rejects invalid maximum frame sizes', () {
      for (final size in [-1, 0, 0x100000000]) {
        expect(
          () => LengthPrefixedFraming(maximum_frame_size: size),
          throwsArgumentError,
        );
      }
    });

    test('encodes an unsigned big-endian length header', () {
      final framing = LengthPrefixedFraming();

      final encoded = framing.encode(Uint8List.fromList([10, 20, 30]));

      expect(encoded, [0, 0, 0, 3, 10, 20, 30]);
    });

    test('encodes lengths spanning multiple header bytes', () {
      final framing = LengthPrefixedFraming();

      final encoded = framing.encode(Uint8List(256));

      expect(encoded.sublist(0, 4), [0, 0, 1, 0]);
      expect(encoded.length, 260);
    });

    test('rejects empty outgoing frames', () {
      final framing = LengthPrefixedFraming();

      expect(() => framing.encode(Uint8List(0)), throwsA(invalid_length));
    });

    test('rejects oversized outgoing frames', () {
      final framing = LengthPrefixedFraming(maximum_frame_size: 4);

      expect(() => framing.encode(Uint8List(5)), throwsA(invalid_length));
    });

    test('encoded frame does not retain the source buffer', () {
      final framing = LengthPrefixedFraming();
      final payload = Uint8List.fromList([1, 2, 3]);

      final encoded = framing.encode(payload);

      payload[0] = 99;

      expect(encoded, [0, 0, 0, 3, 1, 2, 3]);
    });
  });

  group('incremental decoding', () {
    test('decodes a complete frame', () async {
      final framing = LengthPrefixedFraming();
      final payload = Uint8List.fromList([1, 2, 3]);

      final decoded = await framing
          .decode(Stream.value(framing.encode(payload)))
          .toList();

      expect(decoded, [payload]);
    });

    test('accepts a payload at the configured size limit', () async {
      final framing = LengthPrefixedFraming(maximum_frame_size: 4);

      final payload = Uint8List.fromList([1, 2, 3, 4]);

      final decoded = await framing
          .decode(Stream.value(framing.encode(payload)))
          .toList();

      expect(decoded, [payload]);
    });

    test('handles every possible two-chunk split', () async {
      final framing = LengthPrefixedFraming();
      final payload = Uint8List.fromList([10, 20, 30, 40, 50]);
      final frame = framing.encode(payload);

      // Exercise every boundary within the header and payload
      // rather than selecting only convenient fragment sizes.
      for (var split = 1; split < frame.length; split++) {
        final chunks = [frame.sublist(0, split), frame.sublist(split)];

        final decoded = await framing
            .decode(Stream.fromIterable(chunks))
            .toList();

        expect(decoded, [payload], reason: 'Frame split at byte $split');
      }
    });

    test('handles individual byte fragments', () async {
      final framing = LengthPrefixedFraming();
      final payload = Uint8List.fromList([1, 2, 3, 4]);
      final frame = framing.encode(payload);

      final chunks = frame.map((byte) => Uint8List.fromList([byte]));

      final decoded = await framing
          .decode(Stream.fromIterable(chunks))
          .toList();

      expect(decoded, [payload]);
    });

    test('decodes multiple frames in one transport chunk', () async {
      final framing = LengthPrefixedFraming();

      final payloads = [
        Uint8List.fromList([1, 2]),
        Uint8List.fromList([3, 4, 5]),
        Uint8List.fromList([6]),
      ];

      final chunk = Uint8List.fromList([
        for (final payload in payloads) ...framing.encode(payload),
      ]);

      final decoded = await framing.decode(Stream.value(chunk)).toList();

      expect(decoded, payloads);
    });

    test('handles fragmented and coalesced frames together', () async {
      final framing = LengthPrefixedFraming();

      final first = framing.encode(Uint8List.fromList([1, 2, 3]));

      final second = framing.encode(Uint8List.fromList([4, 5, 6]));

      final chunks = [
        first.sublist(0, 2),
        Uint8List.fromList([...first.sublist(2), ...second.sublist(0, 5)]),
        second.sublist(5),
      ];

      final decoded = await framing
          .decode(Stream.fromIterable(chunks))
          .toList();

      expect(decoded, [
        [1, 2, 3],
        [4, 5, 6],
      ]);
    });

    test('ignores empty transport chunks', () async {
      final framing = LengthPrefixedFraming();
      final payload = Uint8List.fromList([1, 2, 3]);
      final frame = framing.encode(payload);

      final chunks = [
        Uint8List(0),
        frame.sublist(0, 2),
        Uint8List(0),
        frame.sublist(2),
        Uint8List(0),
      ];

      final decoded = await framing
          .decode(Stream.fromIterable(chunks))
          .toList();

      expect(decoded, [payload]);
    });

    test('maintains independent decoder state per stream', () async {
      final framing = LengthPrefixedFraming();

      final first = framing.encode(Uint8List.fromList([1, 2]));

      final second = framing.encode(Uint8List.fromList([3, 4, 5]));

      final results = await Future.wait([
        framing
            .decode(
              Stream.fromIterable([first.sublist(0, 2), first.sublist(2)]),
            )
            .toList(),
        framing
            .decode(
              Stream.fromIterable([second.sublist(0, 5), second.sublist(5)]),
            )
            .toList(),
      ]);

      expect(results, [
        [
          [1, 2],
        ],
        [
          [3, 4, 5],
        ],
      ]);
    });
  });

  group('protocol failures and termination', () {
    test('rejects empty incoming frames', () async {
      final framing = LengthPrefixedFraming();

      await expectLater(
        framing.decode(Stream.value(_length_header(0))),
        emitsError(invalid_length),
      );
    });

    test('rejects oversized headers without awaiting payload', () async {
      final framing = LengthPrefixedFraming(maximum_frame_size: 4);

      // No payload is supplied. Length validation must happen
      // immediately after the complete header is received.
      await expectLater(
        framing.decode(Stream.value(_length_header(5))),
        emitsError(invalid_length),
      );
    });

    test('rejects the maximum unsigned wire length', () async {
      final framing = LengthPrefixedFraming();

      await expectLater(
        framing.decode(Stream.value(_length_header(0xffffffff))),
        emitsError(invalid_length),
      );
    });

    test('rejects incomplete frame headers', () async {
      final framing = LengthPrefixedFraming();

      for (var length = 1; length < 4; length++) {
        await expectLater(
          framing.decode(Stream.value(Uint8List(length))),
          emitsError(incomplete_frame),
        );
      }
    });

    test('rejects incomplete frame payloads', () async {
      final framing = LengthPrefixedFraming();
      final frame = framing.encode(Uint8List.fromList([1, 2, 3]));

      for (var length = 4; length < frame.length; length++) {
        await expectLater(
          framing.decode(Stream.value(frame.sublist(0, length))),
          emitsError(incomplete_frame),
        );
      }
    });

    test('emits completed frames before reporting truncation', () async {
      final framing = LengthPrefixedFraming();

      final chunk = Uint8List.fromList([
        ...framing.encode(Uint8List.fromList([1, 2])),
        ..._length_header(3),
        99,
      ]);

      await expectLater(
        framing.decode(Stream.value(chunk)),
        emitsInOrder([
          equals([1, 2]),
          emitsError(incomplete_frame),
          emitsDone,
        ]),
      );
    });

    test('accepts termination without incoming bytes', () async {
      final framing = LengthPrefixedFraming();

      final decoded = await framing
          .decode(const Stream<Uint8List>.empty())
          .toList();

      expect(decoded, isEmpty);
    });

    test('preserves incoming transport failures', () async {
      final framing = LengthPrefixedFraming();
      final failure = StateError('Controlled transport failure.');

      await expectLater(
        framing.decode(Stream<Uint8List>.error(failure)),
        emitsError(same(failure)),
      );
    });
  });

  group('stream consumption', () {
    test('does not process later frames after cancellation', () async {
      final framing = LengthPrefixedFraming();

      final chunk = Uint8List.fromList([
        ...framing.encode(Uint8List.fromList([1, 2])),
        ..._length_header(0),
      ]);

      // The second frame is invalid. Consuming only the first
      // must not cause the decoder to process the invalid header.
      final decoded = await framing
          .decode(Stream.value(chunk))
          .take(1)
          .toList();

      expect(decoded, [
        [1, 2],
      ]);
    });

    test('propagates cancellation to the incoming stream', () async {
      final framing = LengthPrefixedFraming();
      final cancelled = Completer<void>();

      final controller = StreamController<Uint8List>(
        onCancel: () {
          cancelled.complete();
        },
      );

      final result = framing.decode(controller.stream).take(1).toList();

      controller.add(framing.encode(Uint8List.fromList([1, 2])));

      expect(await result, [
        [1, 2],
      ]);

      await cancelled.future;
      await controller.close();

      expect(cancelled.isCompleted, isTrue);
    });
  });
}

/// Constructs a raw length header declaring the supplied [length].
///
/// Returns a four-byte unsigned, big-endian representation.
/// Used to verify malformed and incomplete incoming frames without
/// passing through the production frame encoder.
Uint8List _length_header(int length) {
  final header = ByteData(4);

  header.setUint32(0, length, Endian.big);

  return header.buffer.asUint8List();
}
