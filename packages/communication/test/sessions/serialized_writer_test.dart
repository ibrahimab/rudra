import 'dart:async';
import 'dart:typed_data';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_communication/src/sessions/serialized_writer.dart';
import 'package:test/test.dart';

/// Verifies outbound ordering, capacity and failure isolation.
void main() {
  test('construction performs no transport writes', () {
    final writer = SerializedWriter(
      send: (_) async {
        fail('Construction must not initiate transport writes.');
      },
    );

    expect(writer.outstanding, 0);
    expect(writer.is_stopped, isFalse);
  });

  test('serializes writes in submission order', () async {
    final first_entered = Completer<void>();
    final second_entered = Completer<void>();
    final first_release = Completer<void>();
    final second_release = Completer<void>();

    final first_frame = Uint8List.fromList([1]);
    final second_frame = Uint8List.fromList([2]);

    final sent = <Uint8List>[];

    final writer = SerializedWriter(
      send: (frame) async {
        sent.add(frame);

        if (identical(frame, first_frame)) {
          first_entered.complete();
          await first_release.future;
          return;
        }

        expect(frame, same(second_frame));

        second_entered.complete();
        await second_release.future;
      },
    );

    final first = writer.write(first_frame);
    final second = writer.write(second_frame);

    await first_entered.future;

    expect(sent, [first_frame]);
    expect(second_entered.isCompleted, isFalse);
    expect(writer.outstanding, 2);

    first_release.complete();

    await first;
    await second_entered.future;

    expect(sent, [first_frame, second_frame]);
    expect(writer.outstanding, 1);

    second_release.complete();

    await second;
    await writer.done;

    expect(writer.outstanding, 0);
  });

  test('enforces outstanding capacity without stopping execution', () async {
    final entered = Completer<void>();
    final release = Completer<void>();

    var send_count = 0;

    final writer = SerializedWriter(
      maximum_outstanding: 1,
      send: (_) async {
        send_count++;

        if (send_count == 1) {
          entered.complete();
          await release.future;
        }
      },
    );

    final first = writer.write(Uint8List.fromList([1]));

    await entered.future;

    await expectLater(
      writer.write(Uint8List.fromList([2])),
      throwsA(
        isA<MessageSessionException>().having(
          (error) => error.code,
          'code',
          MessageSessionErrorCode.capacity_exceeded,
        ),
      ),
    );

    expect(writer.is_stopped, isFalse);
    expect(writer.outstanding, 1);

    release.complete();

    await first;

    await writer.write(Uint8List.fromList([3]));

    expect(send_count, 2);
    expect(writer.outstanding, 0);
  });

  test('transport failure prevents subsequent transport writes', () async {
    final entered = Completer<void>();
    final release = Completer<void>();

    final failure = StateError('Controlled transport write failure.');

    var send_count = 0;

    final writer = SerializedWriter(
      send: (_) async {
        send_count++;

        entered.complete();

        await release.future;

        throw failure;
      },
    );

    final first = writer.write(Uint8List.fromList([1]));
    final second = writer.write(Uint8List.fromList([2]));

    final first_failed = expectLater(first, throwsA(same(failure)));

    final second_failed = expectLater(second, throwsA(same(failure)));

    await entered.future;

    release.complete();

    await Future.wait([first_failed, second_failed]);
    await writer.done;

    expect(writer.is_stopped, isTrue);
    expect(writer.outstanding, 0);
    expect(send_count, 1);

    await expectLater(
      writer.write(Uint8List.fromList([3])),
      throwsA(same(failure)),
    );
  });

  test('handles synchronous transport failures', () async {
    final failure = StateError('Controlled synchronous failure.');

    final writer = SerializedWriter(
      send: (_) {
        throw failure;
      },
    );

    await expectLater(
      writer.write(Uint8List.fromList([1])),
      throwsA(same(failure)),
    );

    await writer.done;

    expect(writer.is_stopped, isTrue);
    expect(writer.outstanding, 0);
  });

  test('stop prevents queued writes from reaching transport', () async {
    final entered = Completer<void>();
    final release = Completer<void>();

    var send_count = 0;

    final writer = SerializedWriter(
      send: (_) async {
        send_count++;

        entered.complete();

        await release.future;
      },
    );

    final first = writer.write(Uint8List.fromList([1]));
    final second = writer.write(Uint8List.fromList([2]));

    final second_failed = expectLater(
      second,
      throwsA(
        isA<MessageSessionException>().having(
          (error) => error.code,
          'code',
          MessageSessionErrorCode.session_closed,
        ),
      ),
    );

    await entered.future;

    writer.stop();
    writer.stop();

    expect(writer.is_stopped, isTrue);

    release.complete();

    await first;
    await second_failed;
    await writer.done;

    expect(writer.outstanding, 0);
    expect(send_count, 1);
  });

  test('stopped writer rejects new writes', () async {
    final writer = SerializedWriter(
      send: (_) async {
        fail('Stopped writer must not initiate transport writes.');
      },
    );

    writer.stop();

    await expectLater(
      writer.write(Uint8List.fromList([1])),
      throwsA(
        isA<MessageSessionException>().having(
          (error) => error.code,
          'code',
          MessageSessionErrorCode.session_closed,
        ),
      ),
    );

    await writer.done;

    expect(writer.outstanding, 0);
  });

  test('rejects invalid outstanding capacity', () {
    expect(
      () => SerializedWriter(send: (_) async {}, maximum_outstanding: 0),
      throwsArgumentError,
    );
  });
}
