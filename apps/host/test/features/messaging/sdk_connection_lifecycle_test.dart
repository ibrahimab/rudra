import 'dart:async';
import 'dart:io';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_host/rudra_host.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

import '../../support/loopback_host_transport.dart';
import '../../support/test_host_ownership_provider.dart';

/// Verifies independently composed SDK connections against a real host.
void main() {
  test('independent SDK lifecycles share one authoritative host', () async {
    const timeout = Duration(seconds: 10);
    const owner = 'trusted-owner';

    final directory = await Directory.systemTemp.createTemp(
      'rudra-sdk-connection-',
    );

    addTearDown(() => directory.delete(recursive: true));

    final scope = await directory.resolveSymbolicLinks();

    final transport = LoopbackHostTransport();
    final ownership = TestHostOwnershipProvider();

    final composition = HostComposition(
      identity_provider: const _TestIdentityProvider(owner),
      ownership_provider: ownership,
      data_directory: directory,
      target_id: 'local-macos',
      communication_factory: ({required codecs, required handlers}) {
        return Communication(
          transport: transport,
          codecs: codecs,
          handlers: handlers,
          options: const MessageSessionOptions(request_timeout: timeout),
        );
      },
    );

    final shutdown = Completer<void>();
    final ready = Completer<void>();

    final running = composition.run(
      shutdown: shutdown.future,
      on_ready: (os_user_id, workflow) {
        expect(os_user_id, owner);
        expect(workflow, isNull);

        ready.complete();
      },
    );

    running.ignore();

    addTearDown(() async {
      if (!shutdown.isCompleted) {
        shutdown.complete();
      }

      await running.timeout(timeout);
    });

    await Future.any<void>([
      ready.future,
      running.then<void>((_) {
        throw StateError('Host terminated before readiness.');
      }),
    ]).timeout(timeout);

    expect(ownership.is_owned, isTrue);
    expect(await composition.database_file.exists(), isFalse);

    final first_connections = <Communication>[];
    final second_connections = <Communication>[];

    /// Creates an SDK with independent communication ownership.
    ///
    /// [connections] records constructed communication instances
    /// so replacement and disposal can be verified independently.
    RudraSdk create_sdk(List<Communication> connections) {
      final sdk = RudraSdk(
        target_id: 'local-macos',
        inspector: _UnusedInspector(),
        connection_setup: () {
          return (scope_directory: scope, os_user_id: owner);
        },
        communication_factory: ({required codecs, required handlers}) {
          final communication = Communication(
            transport: transport,
            codecs: codecs,
            handlers: handlers,
            options: const MessageSessionOptions(request_timeout: timeout),
          );

          connections.add(communication);

          return communication;
        },
      );

      addTearDown(() => sdk.close().timeout(timeout));

      return sdk;
    }

    final first = create_sdk(first_connections);
    final second = create_sdk(second_connections);

    expect(first_connections, isEmpty);
    expect(second_connections, isEmpty);

    await Future.wait<void>([first.connect(), second.connect()])
        .timeout(timeout);

    expect(first.is_connected, isTrue);
    expect(second.is_connected, isTrue);

    expect(first_connections, hasLength(1));
    expect(second_connections, hasLength(1));

    expect(first_connections.single, isNot(same(second_connections.single)));

    final previous = first_connections.single;

    await first.reconnect().timeout(timeout);

    expect(first_connections, hasLength(2));
    expect(previous.resources_released, isTrue);

    expect(first.is_connected, isTrue);
    expect(second.is_connected, isTrue);

    // Replacing one SDK connection cannot replace another SDK's
    // independently owned communication lifecycle.
    expect(second_connections, hasLength(1));

    await first.close().timeout(timeout);

    expect(first.resources_released, isTrue);
    expect(first.is_connected, isFalse);

    expect(second.is_connected, isTrue);
    expect(ownership.is_owned, isTrue);

    expect(await composition.database_file.exists(), isFalse);

    // Host shutdown invalidates the remaining frontend connection.
    shutdown.complete();

    await running.timeout(timeout);
    await second_connections.single.done.timeout(timeout);

    expect(second.is_connected, isFalse);
    expect(second.resources_released, isTrue);
    expect(ownership.is_owned, isFalse);

    // Reconnection to an unavailable host fails explicitly.
    await expectLater(second.reconnect().timeout(timeout), throwsStateError);

    expect(second_connections, hasLength(2));
    expect(second.resources_released, isTrue);

    expect(await composition.database_file.exists(), isFalse);
  });
}

/// Supplies deterministic trusted identity for host integration.
///
/// Example:
/// ```dart
/// const provider = _TestIdentityProvider('trusted-owner');
///
/// expect(await provider.resolve(), 'trusted-owner');
/// ```
final class _TestIdentityProvider implements HostIdentityProvider {
  /// Retains the trusted fixture [os_user_id].
  const _TestIdentityProvider(this.os_user_id);

  /// Authenticated owner represented by the fixture.
  final String os_user_id;

  /// Returns the retained trusted operating-system identity.
  @override
  Future<String> resolve() async => os_user_id;
}

/// Rejects filesystem inspection in a connection-only integration test.
///
/// Example:
/// ```dart
/// final sdk = RudraSdk(
///   target_id: 'local-macos',
///   inspector: _UnusedInspector(),
/// );
/// ```
final class _UnusedInspector implements TargetInspector {
  /// Rejects the unexpected inspection operation in [invocation].
  ///
  /// Throws [UnsupportedError] for every target operation.
  @override
  Never noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'Unexpected filesystem inspection: ${invocation.memberName}',
    );
  }
}
