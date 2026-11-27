import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_communication/rudra_communication.dart';
import 'package:test/test.dart';

void main() {
  test('construction and closure never resolve connectivity', () async {
    final sdk = RudraSdk(
      communication_factory: ({required codecs, required handlers}) {
        fail('Inactive SDK must not construct Communication.');
      },
    );

    expect(sdk.is_connected, isFalse);
    expect(sdk.resources_released, isTrue);

    await sdk.close();

    await expectLater(sdk.connect(), throwsStateError);
    await expectLater(sdk.reconnect(), throwsStateError);
  });

  test(
    'failed establishment releases resources and retains explicit selection',
    () async {
      final first = _UnavailableTransport();
      final second = _UnavailableTransport();
      final sdk = RudraSdk();
      addTearDown(sdk.close);

      await expectLater(
        sdk.connect(ConnectionParams(transport: first)),
        throwsStateError,
      );
      expect(first.attempts, 1);
      expect(sdk.is_connected, isFalse);
      expect(sdk.resources_released, isTrue);

      await expectLater(sdk.reconnect(), throwsStateError);
      expect(first.attempts, 2);

      await expectLater(
        sdk.reconnect(ConnectionParams(transport: second)),
        throwsStateError,
      );
      expect(first.attempts, 2);
      expect(second.attempts, 1);
      expect(sdk.resources_released, isTrue);
    },
  );
}

final class _UnavailableTransport implements Transport {
  int attempts = 0;

  @override
  Future<TransportConnection> connect() async {
    attempts++;
    throw StateError('Fixture endpoint is unavailable.');
  }

  @override
  Future<TransportListener> listen() async =>
      fail('Expected client execution.');
}
