import 'dart:async';
import 'dart:io';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_host/rudra_host.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_target_macos/rudra_target_macos.dart';
import 'package:test/test.dart';

import '../../support/loopback_host_transport.dart';
import '../../support/test_host_ownership_provider.dart';

/// Verifies authoritative filesystem inspection through the public SDK.
///
/// Uses independently configured host and client communication
/// instances with real application messaging and persistence composition.
void main() {
  const directory_path = r'C:\Users\example\Downloads';

  test(
    'reconstructs a large ordered listing without initializing SQLite',
    () async {
      const observation_count = 300;

      final inspector = _FixtureInspector(child_count: observation_count);

      final fixture = await _HostFixture.create(inspector: inspector);

      final sdk = await fixture.connect();

      final listing = await sdk.filesystem.list(
        directory: TargetPath(directory_path),
      );

      expect(listing.target_id, _HostFixture.target_id);
      expect(listing.directory.value, directory_path);
      expect(listing.entries, hasLength(observation_count));
      expect(listing.issues, isEmpty);
      expect(listing.is_complete, isTrue);

      expect(
        listing.entries.map((entry) => entry.path.value),
        List.generate(
          observation_count,
          (index) => '$directory_path\\file-$index.txt',
        ),
      );

      expect(
        listing.entries.map((entry) => entry.metadata.logical_size_bytes),
        List.generate(observation_count, (index) => index),
      );

      // A large transfer must retain one logical enumeration
      // rather than reopening the directory for each batch.
      expect(inspector.enumeration_count, 1);
      expect(inspector.inspection_count, observation_count);
      expect(inspector.release_count, 1);

      expect(
        await (await fixture.composition.resolve_database()).exists(),
        isFalse,
      );

      final state = await sdk.read_state();

      expect(state.workflows.current_workflow, isNull);
      expect(
        await (await fixture.composition.resolve_database()).exists(),
        isFalse,
      );
    },
  );

  test(
    'preserves typed failures across multiple observation batches',
    () async {
      const observation_count = 300;
      const failed_index = 4;

      final inspector = _FixtureInspector(
        child_count: observation_count,
        failed_index: failed_index,
      );

      final fixture = await _HostFixture.create(inspector: inspector);

      final sdk = await fixture.connect();

      final listing = await sdk.filesystem.list(
        directory: TargetPath(directory_path),
      );

      expect(listing.is_complete, isFalse);
      expect(listing.entries, hasLength(observation_count - 1));
      expect(listing.issues, hasLength(1));

      final issue = listing.issues.single;

      expect(issue.code, TargetInspectionErrorCode.permissionDenied);
      expect(issue.operation, TargetInspectionOperation.inspect);
      expect(issue.path.value, '$directory_path\\file-$failed_index.txt');

      expect(
        listing.entries.last.path.value,
        '$directory_path\\file-${observation_count - 1}.txt',
      );

      expect(inspector.enumeration_count, 1);
      expect(inspector.inspection_count, observation_count);
      expect(inspector.release_count, 1);

      expect(
        await (await fixture.composition.resolve_database()).exists(),
        isFalse,
      );
    },
  );

  test('returns a complete listing for an empty directory', () async {
    final inspector = _FixtureInspector(child_count: 0);

    final fixture = await _HostFixture.create(inspector: inspector);

    final sdk = await fixture.connect();

    final listing = await sdk.filesystem.list(
      directory: TargetPath(directory_path),
    );

    expect(listing.is_complete, isTrue);
    expect(listing.entries, isEmpty);
    expect(listing.issues, isEmpty);

    expect(inspector.enumeration_count, 1);
    expect(inspector.inspection_count, 0);
    expect(inspector.release_count, 1);
  });

  test(
    'independent clients retain independent filesystem inspections',
    () async {
      const observation_count = 150;

      final inspector = _FixtureInspector(child_count: observation_count);

      final fixture = await _HostFixture.create(inspector: inspector);

      final first = await fixture.connect();
      final second = await fixture.connect();

      final directory = TargetPath(directory_path);

      final listings = await Future.wait([
        first.filesystem.list(directory: directory),
        second.filesystem.list(directory: directory),
      ]);

      for (final listing in listings) {
        expect(listing.is_complete, isTrue);
        expect(listing.entries, hasLength(observation_count));
      }

      expect(inspector.enumeration_count, 2);
      expect(inspector.inspection_count, observation_count * 2);
      expect(inspector.release_count, 2);

      await first.close();

      final subsequent = await second.filesystem.list(directory: directory);

      expect(subsequent.is_complete, isTrue);
      expect(second.is_connected, isTrue);
      expect(inspector.enumeration_count, 3);
    },
  );

  test('rejects an unsupported target before native inspection', () async {
    final inspector = _FixtureInspector(child_count: 1);

    final fixture = await _HostFixture.create(inspector: inspector);

    final sdk = await fixture.connect(target_id: 'unsupported-target');

    await expectLater(
      sdk.filesystem.list(directory: TargetPath(directory_path)),
      throwsA(
        isA<MessageSessionException>().having(
          (error) => error.code,
          'code',
          MessageSessionErrorCode.handler_failed,
        ),
      ),
    );

    expect(inspector.enumeration_count, 0);
    expect(inspector.inspection_count, 0);
    expect(sdk.is_connected, isTrue);
  });

  test('rejects inconsistent authenticated peer ownership', () async {
    final inspector = _FixtureInspector(child_count: 1);

    final fixture = await _HostFixture.create(
      inspector: inspector,
      server_peer_override: 'different-owner',
    );

    final sdk = await fixture.connect();

    await expectLater(
      sdk.filesystem.list(directory: TargetPath(directory_path)),
      throwsA(isA<MessageSessionException>()),
    );

    expect(inspector.enumeration_count, 0);
    expect(inspector.inspection_count, 0);

    expect(
      await (await fixture.composition.resolve_database()).exists(),
      isFalse,
    );
  });

  test(
    'connection replacement never resumes an abandoned inspection',
    () async {
      final inspector = _FixtureInspector(child_count: 1);

      final fixture = await _HostFixture.create(inspector: inspector);

      final barrier = LoopbackResponseBarrier();

      fixture.transport.next_response_barrier = barrier;

      addTearDown(barrier.release);

      final sdk = await fixture.connect();

      final pending = sdk.filesystem.list(
        directory: TargetPath(directory_path),
      );

      final failure = expectLater(
        pending,
        throwsA(anyOf(isA<StateError>(), isA<MessageSessionException>())),
      );

      // The original inspection is admitted, but its opening
      // response has not reached the frontend.
      await barrier.entered.timeout(_HostFixture.timeout);

      expect(inspector.enumeration_count, 0);

      await sdk.reconnect().timeout(_HostFixture.timeout);

      await failure;

      expect(sdk.is_connected, isTrue);
      expect(inspector.enumeration_count, 0);

      final listing = await sdk.filesystem.list(
        directory: TargetPath(directory_path),
      );

      expect(listing.is_complete, isTrue);
      expect(listing.entries, hasLength(1));

      expect(inspector.enumeration_count, 1);
      expect(inspector.inspection_count, 1);
      expect(inspector.release_count, 1);
    },
  );

  test('inspects actual macOS filesystem entries through the host', () async {
    final directory = await Directory.systemTemp.createTemp(
      'rudra-native-inspection-',
    );

    addTearDown(() => directory.delete(recursive: true));

    final root = await directory.resolveSymbolicLinks();

    await File('$root/example.txt').writeAsString('Rudra');
    await Directory('$root/child').create();

    final fixture = await _HostFixture.create(
      inspector: MacOsTargetInspector(),
    );

    final sdk = await fixture.connect();

    final listing = await sdk.filesystem.list(directory: TargetPath(root));

    expect(listing.is_complete, isTrue);
    expect(listing.entries, hasLength(2));

    final entries = {
      for (final entry in listing.entries) entry.path.value: entry,
    };

    expect(entries['$root/example.txt']!.kind, FilesystemEntryKind.regularFile);

    expect(entries['$root/example.txt']!.metadata.logical_size_bytes, 5);

    expect(entries['$root/child']!.kind, FilesystemEntryKind.directory);

    expect(
      await (await fixture.composition.resolve_database()).exists(),
      isFalse,
    );
  }, skip: !Platform.isMacOS);
}

/// Owns an independently configured host integration environment.
final class _HostFixture {
  /// Creates a fixture retaining its configured host resources.
  _HostFixture({required this.composition, required this.transport});

  /// Maximum duration of controlled lifecycle operations.
  static const Duration timeout = Duration(seconds: 15);

  /// Trusted authenticated owner of the fixture host.
  static const String owner = 'trusted-owner';

  /// Configured filesystem target.
  static const String target_id = 'test-target';

  /// Host application composition and persistence owner.
  final HostComposition composition;

  /// Controlled authenticated host communication transport.
  final LoopbackHostTransport transport;

  /// Starts a host using the supplied filesystem [inspector].
  ///
  /// [server_peer_override] optionally supplies inconsistent
  /// server-side authentication evidence.
  ///
  /// Returns after verified host readiness. Test teardown
  /// releases all retained resources.
  static Future<_HostFixture> create({
    required TargetInspector inspector,
    String? server_peer_override,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'rudra-sdk-filesystem-',
    );

    addTearDown(() => directory.delete(recursive: true));

    final scope = await directory.resolveSymbolicLinks();

    final transport = LoopbackHostTransport(
      os_user_id: owner,
      server_peer_override: server_peer_override,
    );

    final ownership = TestHostOwnershipProvider();

    final composition = HostComposition(
      identity_provider: const _IdentityProvider(),
      ownership_provider: ownership,
      resolve_database: () => File('$scope/rudra.sqlite'),
      target_id: target_id,
      inspector: inspector,
      communication_factory: ({required codecs, required handlers}) {
        return Communication(
          listening_transports: [transport],
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

      expect(ownership.is_owned, isFalse);
    });

    await Future.any<void>([
      ready.future,
      running.then<void>((_) {
        throw StateError('Host terminated before readiness.');
      }),
    ]).timeout(timeout);

    return _HostFixture(composition: composition, transport: transport);
  }

  /// Establishes an independently owned authenticated SDK connection.
  ///
  /// [target_id] identifies the requested filesystem environment.
  ///
  /// Returns a connected SDK registered for test resource disposal.
  Future<RudraSdk> connect({String target_id = _HostFixture.target_id}) async {
    final sdk = RudraSdk(
      target_id: target_id,

      communication_factory: ({required codecs, required handlers}) {
        return Communication(
          codecs: codecs,
          handlers: handlers,
          options: const MessageSessionOptions(request_timeout: timeout),
        );
      },
    );

    addTearDown(() => sdk.close().timeout(timeout));

    await sdk.connect(ConnectionParams(transport: transport)).timeout(timeout);

    return sdk;
  }
}

/// Supplies trusted host ownership for filesystem integration.
final class _IdentityProvider implements HostIdentityProvider {
  /// Creates a deterministic host identity provider.
  const _IdentityProvider();

  /// Returns the trusted fixture owner.
  @override
  Future<String> resolve() async => _HostFixture.owner;
}

/// Supplies deterministic target-native filesystem observations.
final class _FixtureInspector implements TargetInspector {
  /// Creates an inspector with [child_count] directory entries.
  ///
  /// [failed_index] optionally identifies an inaccessible child.
  _FixtureInspector({required this.child_count, this.failed_index});

  /// Number of directory children supplied by enumeration.
  final int child_count;

  /// Optional child index producing a typed inspection failure.
  final int? failed_index;

  /// Number of directory enumeration lifecycles initiated.
  int enumeration_count = 0;

  /// Number of directory enumeration lifecycles released.
  int release_count = 0;

  /// Number of child inspection operations attempted.
  int inspection_count = 0;

  /// Enumerates configured children of [path] in native order.
  ///
  /// Returns a lazy stream retaining the original directory spelling.
  @override
  Stream<TargetPath> list_directory(TargetPath path) async* {
    enumeration_count++;

    try {
      for (var index = 0; index < child_count; index++) {
        yield TargetPath('${path.value}\\file-$index.txt');
      }
    } finally {
      release_count++;
    }
  }

  /// Inspects the configured child identified by [path].
  ///
  /// Returns its deterministic metadata or throws a typed
  /// inspection failure for the configured inaccessible child.
  @override
  Future<FilesystemEntry> inspect(TargetPath path) async {
    inspection_count++;

    final match = RegExp(r'file-(\d+)\.txt$').firstMatch(path.value);

    if (match == null) {
      throw StateError('Unexpected fixture path.');
    }

    final index = int.parse(match.group(1)!);

    if (index == failed_index) {
      throw TargetInspectionException(
        code: TargetInspectionErrorCode.permissionDenied,
        operation: TargetInspectionOperation.inspect,
        path: path,
        message: 'Permission denied.',
      );
    }

    return FilesystemEntry(
      path: path,
      kind: FilesystemEntryKind.regularFile,
      metadata: FilesystemMetadata(logical_size_bytes: index),
    );
  }

  /// Rejects inspection operations unrelated to directory listing.
  @override
  Never noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'Unexpected target operation: ${invocation.memberName}',
    );
  }
}
