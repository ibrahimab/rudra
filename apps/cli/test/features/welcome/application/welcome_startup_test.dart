import 'package:rudra_cli/rudra_cli.dart';
import 'package:rudra_cli/src/composition/product_sdk_composition.dart';
import 'package:rudra_cli/src/features/welcome/application/welcome_controller.dart';
import 'package:rudra_cli/src/features/welcome/presentation/bare_welcome_renderer.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies the SDK-backed welcome workflow.
///
/// Uses a controlled TargetInspector implementation.
/// No real user filesystem is inspected or modified.
void main() {
  group('WelcomeController', () {
    test('lists the configured directory through the SDK', () async {
      final directory = TargetPath('/fixture');
      final file = FilesystemEntry(
        path: TargetPath('/fixture/example.txt'),
        kind: FilesystemEntryKind.regularFile,
        metadata: FilesystemMetadata(
          logical_size_bytes: 1024,
          permissions: FilesystemPermissions(posix_mode: 0x1A4),
        ),
      );

      final inspector = _StartupInspector(
        children: [file.path],
        entries: {file.path.value: file},
      );

      final composition = ProductSdkComposition(
        sdk: RudraSdk(target_id: 'fixture-target', inspector: inspector),
        working_directory: directory,
      );

      final output = StringBuffer();
      final errors = StringBuffer();

      final controller = _create_welcome_controller(
        composition: composition,
        output: output,
        error_output: errors,
      );

      // Construction must remain free of inspection.
      expect(inspector.enumeration_count, 0);
      expect(inspector.inspection_count, 0);

      final status = await controller.show();

      expect(status, RudraExitCode.success.value);
      expect(output.toString(), contains('RUDRA'));
      expect(output.toString(), contains('Target: fixture-target'));
      expect(output.toString(), contains('Starting directory: /fixture'));
      expect(output.toString(), contains('example.txt'));
      expect(output.toString(), contains('1.0 KiB'));
      expect(output.toString(), contains('-rw-r--r--'));
      expect(errors.toString(), isEmpty);

      expect(inspector.enumeration_count, 1);
      expect(inspector.inspection_count, 1);
      expect(inspector.listed_path, same(directory));
      expect(inspector.symbolic_link_calls, 0);
    });

    test('renders an empty directory successfully', () async {
      final inspector = _StartupInspector();
      final output = StringBuffer();

      final controller = _create_welcome_controller(
        composition: _composition(inspector),
        output: output,
        error_output: StringBuffer(),
      );

      final status = await controller.show();

      expect(status, RudraExitCode.success.value);
      expect(output.toString(), contains('0 observed entries'));
      expect(inspector.enumeration_count, 1);
      expect(inspector.inspection_count, 0);
    });

    test('preserves partial observations and typed failures', () async {
      final file = FilesystemEntry(
        path: TargetPath('/fixture/good.txt'),
        kind: FilesystemEntryKind.regularFile,
        metadata: FilesystemMetadata(logical_size_bytes: 512),
      );

      final blocked_path = TargetPath('/fixture/blocked.txt');

      final inspector = _StartupInspector(
        children: [file.path, blocked_path],
        entries: {file.path.value: file},
        inspection_failures: {
          blocked_path.value: TargetInspectionException(
            code: TargetInspectionErrorCode.permissionDenied,
            operation: TargetInspectionOperation.inspect,
            path: blocked_path,
            message: 'Permission denied.',
          ),
        },
      );

      final output = StringBuffer();
      final errors = StringBuffer();

      final controller = _create_welcome_controller(
        composition: _composition(inspector),
        output: output,
        error_output: errors,
      );

      final status = await controller.show();

      expect(status, RudraExitCode.inspection_incomplete.value);
      expect(output.toString(), contains('good.txt'));
      expect(output.toString(), contains('WARNING'));
      expect(errors.toString(), contains('permissionDenied'));
      expect(errors.toString(), contains('/fixture/blocked.txt'));
      expect(inspector.inspection_count, 2);
    });

    test('reports directory enumeration failure', () async {
      final directory = TargetPath('/fixture');

      final inspector = _StartupInspector(
        enumeration_failure: TargetInspectionException(
          code: TargetInspectionErrorCode.permissionDenied,
          operation: TargetInspectionOperation.listDirectory,
          path: directory,
          message: 'Cannot enumerate directory.',
        ),
      );

      final output = StringBuffer();
      final errors = StringBuffer();

      final status = await _create_welcome_controller(
        composition: _composition(inspector),
        output: output,
        error_output: errors,
      ).show();

      expect(status, RudraExitCode.inspection_incomplete.value);
      expect(output.toString(), contains('WARNING'));
      expect(errors.toString(), contains('listDirectory'));
      expect(errors.toString(), contains('permissionDenied'));
      expect(inspector.inspection_count, 0);
    });

    test('preserves unsupported-target presentation', () async {
      final output = StringBuffer();

      final controller = _create_welcome_controller(
        composition: null,
        output: output,
        error_output: StringBuffer(),
      );

      final status = await controller.show();

      expect(status, RudraExitCode.success.value);
      expect(
        output.toString(),
        contains('Filesystem inspection is not available'),
      );
      expect(output.toString(), isNot(contains('rudra ls')));
      expect(output.toString(), contains('rudra about'));
    });

    test('propagates unexpected SDK errors', () async {
      final inspector = _StartupInspector(
        unexpected_failure: StateError('Unexpected failure'),
      );

      final controller = _create_welcome_controller(
        composition: _composition(inspector),
        output: StringBuffer(),
        error_output: StringBuffer(),
      );

      await expectLater(controller.show(), throwsA(isA<StateError>()));
    });

    test('accepts an explicitly injected rendering backend', () async {
      final output = StringBuffer();

      final renderer = BareWelcomeRenderer(output: output);

      final controller = WelcomeController(
        sdk: null,
        starting_directory: null,
        renderer: renderer,
      );

      final status = await controller.show();

      expect(status, RudraExitCode.success.value);

      expect(output.toString(), contains('RUDRA  |  READ ONLY'));

      expect(
        output.toString(),
        contains('Filesystem inspection is not available'),
      );
    });
  });

  group('Production CLI welcome startup', () {
    test('runs the SDK-backed welcome without arguments', () async {
      final inspector = _StartupInspector();
      final output = StringBuffer();
      final errors = StringBuffer();

      final cli = RudraCli.product(
        target_composition: _composition(inspector),
        output: output,
        error_output: errors,
      );

      final status = await cli.run([]);

      expect(status, RudraExitCode.success.value);
      expect(output.toString(), contains('RUDRA'));
      expect(output.toString(), contains('0 observed entries'));
      expect(errors.toString(), isEmpty);
      expect(inspector.enumeration_count, 1);
    });

    test('propagates incomplete inspection exit status', () async {
      final inspector = _StartupInspector(
        enumeration_failure: TargetInspectionException(
          code: TargetInspectionErrorCode.permissionDenied,
          operation: TargetInspectionOperation.listDirectory,
          path: TargetPath('/fixture'),
          message: 'Cannot enumerate directory.',
        ),
      );

      final cli = RudraCli.product(
        target_composition: _composition(inspector),
        output: StringBuffer(),
        error_output: StringBuffer(),
      );

      expect(await cli.run([]), RudraExitCode.inspection_incomplete.value);
    });

    test('preserves explicit production commands', () {
      final cli = RudraCli.product(
        target_composition: _composition(_StartupInspector()),
        output: StringBuffer(),
      );

      expect(cli.command_names, containsAll(['about', 'ls']));
      expect(
        cli.module_ids,
        containsAll(['rudra.product.about', 'rudra.product.filesystem']),
      );
    });

    test('retains single-invocation lifecycle', () async {
      final inspector = _StartupInspector();

      final cli = RudraCli.product(
        target_composition: _composition(inspector),
        output: StringBuffer(),
        error_output: StringBuffer(),
      );

      expect(await cli.run([]), RudraExitCode.success.value);

      await expectLater(cli.run([]), throwsStateError);

      expect(inspector.enumeration_count, 1);
    });
  });
}

/// Creates a welcome controller with explicitly composed rendering.
///
/// This test helper preserves readable SDK integration fixtures
/// while exercising the production dependency-injection contract.
///
/// Unlike the previous controller constructor, output sinks
/// are now owned by the concrete rendering backend.
///
/// The helper performs no filesystem inspection or terminal I/O.
WelcomeController _create_welcome_controller({
  required ProductSdkComposition? composition,
  required StringSink output,
  StringSink? error_output,
}) {
  final renderer = BareWelcomeRenderer(
    output: output,
    error_output: error_output,
  );

  return WelcomeController(
    sdk: composition?.sdk,
    starting_directory: composition?.working_directory,
    renderer: renderer,
  );
}

/// Creates an isolated SDK composition for welcome tests.
ProductSdkComposition _composition(TargetInspector inspector) {
  return ProductSdkComposition(
    sdk: RudraSdk(target_id: 'fixture-target', inspector: inspector),
    working_directory: TargetPath('/fixture'),
  );
}

/// Supplies read-only filesystem observations for tests.
///
/// All data and failures are injected. This test double cannot
/// modify the host filesystem.
final class _StartupInspector implements TargetInspector {
  /// Creates a deterministic filesystem inspection fixture.
  _StartupInspector({
    List<TargetPath> children = const [],
    Map<String, FilesystemEntry> entries = const {},
    Map<String, TargetInspectionException> inspection_failures = const {},
    this.enumeration_failure,
    this.unexpected_failure,
  }) : _children = List<TargetPath>.unmodifiable(children),
       _entries = Map<String, FilesystemEntry>.unmodifiable(entries),
       _inspection_failures =
           Map<String, TargetInspectionException>.unmodifiable(
             inspection_failures,
           );

  final List<TargetPath> _children;
  final Map<String, FilesystemEntry> _entries;
  final Map<String, TargetInspectionException> _inspection_failures;

  /// Optional typed directory enumeration failure.
  final TargetInspectionException? enumeration_failure;

  /// Optional unexpected filesystem failure.
  final Object? unexpected_failure;

  /// Number of directory enumeration requests.
  int enumeration_count = 0;

  /// Number of entry inspection requests.
  int inspection_count = 0;

  /// Number of symbolic-link resolution attempts.
  int symbolic_link_calls = 0;

  /// Directory used in the latest enumeration request.
  TargetPath? listed_path;

  /// Enumerates only the configured fixture entries.
  @override
  Stream<TargetPath> list_directory(TargetPath path) async* {
    enumeration_count++;
    listed_path = path;

    if (unexpected_failure != null) {
      throw unexpected_failure!;
    }

    for (final child in _children) {
      yield child;
    }

    if (enumeration_failure != null) {
      throw enumeration_failure!;
    }
  }

  /// Inspects only configured fixture entries.
  @override
  Future<FilesystemEntry> inspect(TargetPath path) async {
    inspection_count++;

    final failure = _inspection_failures[path.value];

    if (failure != null) {
      throw failure;
    }

    final entry = _entries[path.value];

    if (entry == null) {
      throw StateError('Unexpected inspection: ${path.value}');
    }

    return entry;
  }

  /// Rejects unexpected capability discovery.
  @override
  Future<TargetCapabilities> capabilities_for(TargetPath path) async {
    throw StateError('Unexpected capability request: ${path.value}');
  }

  /// Rejects symbolic-link resolution.
  @override
  Future<TargetPath> read_symbolic_link(TargetPath path) async {
    symbolic_link_calls++;

    throw StateError('Unexpected symbolic-link access: ${path.value}');
  }
}
