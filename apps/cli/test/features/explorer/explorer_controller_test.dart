import 'dart:async';

import 'package:rudra_cli/src/features/explorer/application/explorer_controller.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies read-only CLI navigation through the public SDK.
///
/// All filesystem observations are injected.
/// No real user filesystem operations or cleanup occur.
void main() {
  group('ExplorerController', () {
    test('starts at the configured root and sorts entries', () async {
      final apps = _entry('/fixture/apps', FilesystemEntryKind.directory);
      final packages = _entry(
        '/fixture/packages',
        FilesystemEntryKind.directory,
      );
      final file = _entry(
        '/fixture/readme.txt',
        FilesystemEntryKind.regularFile,
      );
      final link = _entry(
        '/fixture/shortcut',
        FilesystemEntryKind.symbolicLink,
      );

      final entries = [file, packages, link, apps];

      final inspector = _ExplorerInspector(
        children: {'/fixture': entries.map((entry) => entry.path).toList()},
        entries: _entry_map(entries),
      );

      final controller = _controller(inspector);

      expect(controller.model, isNull);
      expect(inspector.listed_directories, isEmpty);

      final model = await controller.start();

      expect(model.current_directory.value, '/fixture');
      expect(model.root_directory.value, '/fixture');
      expect(model.history, isEmpty);
      expect(model.can_go_back, isFalse);
      expect(model.selected_index, 0);
      expect(model.selected_entry?.path.value, '/fixture/apps');

      expect(
        model.entries.map((entry) => entry.path.value),
        orderedEquals([
          '/fixture/apps',
          '/fixture/packages',
          '/fixture/readme.txt',
          '/fixture/shortcut',
        ]),
      );

      expect(inspector.listed_directories, ['/fixture']);
      expect(inspector.inspected_paths, hasLength(4));
      expect(inspector.symbolic_link_calls, 0);

      // Presentation state cannot be modified externally.
      expect(() => model.entries.clear(), throwsUnsupportedError);
      expect(
        () => model.history.add(TargetPath('/outside')),
        throwsUnsupportedError,
      );
    });

    test('moves selection and clamps at the boundaries', () async {
      final first = _entry('/fixture/a.txt', FilesystemEntryKind.regularFile);
      final second = _entry('/fixture/b.txt', FilesystemEntryKind.regularFile);

      final inspector = _ExplorerInspector(
        children: {
          '/fixture': [first.path, second.path],
        },
        entries: _entry_map([first, second]),
      );

      final controller = _controller(inspector);

      await controller.start();

      expect(controller.move_selection(-1).selected_index, 0);
      expect(controller.move_selection(1).selected_index, 1);
      expect(controller.move_selection(20).selected_index, 1);
      expect(controller.move_selection(-20).selected_index, 0);

      // Moving selection does not trigger another inspection.
      expect(inspector.listed_directories, ['/fixture']);
    });

    test('opens a directory and returns through history', () async {
      final apps = _entry('/fixture/apps', FilesystemEntryKind.directory);
      final main_file = _entry(
        '/fixture/apps/main.dart',
        FilesystemEntryKind.regularFile,
      );

      final inspector = _ExplorerInspector(
        children: {
          '/fixture': [apps.path],
          '/fixture/apps': [main_file.path],
        },
        entries: _entry_map([apps, main_file]),
      );

      final controller = _controller(inspector);

      await controller.start();

      final child = await controller.open_selected();

      expect(child.current_directory.value, '/fixture/apps');
      expect(child.can_go_back, isTrue);
      expect(
        child.history.map((path) => path.value),
        orderedEquals(['/fixture']),
      );
      expect(child.selected_entry?.path.value, main_file.path.value);

      final root = await controller.back();

      expect(root.current_directory.value, '/fixture');
      expect(root.history, isEmpty);
      expect(root.can_go_back, isFalse);

      expect(
        inspector.listed_directories,
        orderedEquals(['/fixture', '/fixture/apps', '/fixture']),
      );

      // Back at the root cannot escape to its parent.
      final unchanged = await controller.back();

      expect(identical(unchanged, root), isTrue);
      expect(inspector.listed_directories, hasLength(3));
    });

    test('does not open regular files or symbolic links', () async {
      final file = _entry('/fixture/a.txt', FilesystemEntryKind.regularFile);
      final link = _entry('/fixture/z-link', FilesystemEntryKind.symbolicLink);

      final inspector = _ExplorerInspector(
        children: {
          '/fixture': [file.path, link.path],
        },
        entries: _entry_map([file, link]),
      );

      final controller = _controller(inspector);

      final initial = await controller.start();

      expect(initial.selected_entry?.kind, FilesystemEntryKind.regularFile);

      final after_file = await controller.open_selected();

      expect(identical(after_file, initial), isTrue);

      controller.move_selection(1);

      expect(
        controller.model?.selected_entry?.kind,
        FilesystemEntryKind.symbolicLink,
      );

      final after_link = await controller.open_selected();

      expect(after_link.current_directory.value, '/fixture');
      expect(inspector.listed_directories, ['/fixture']);
      expect(inspector.symbolic_link_calls, 0);
    });

    test('handles an empty directory without selection', () async {
      final inspector = _ExplorerInspector();

      final controller = _controller(inspector);

      final model = await controller.start();

      expect(model.entries, isEmpty);
      expect(model.selected_index, isNull);
      expect(model.selected_entry, isNull);

      expect(controller.move_selection(1).selected_index, isNull);

      final unchanged = await controller.open_selected();

      expect(unchanged.current_directory.value, '/fixture');
      expect(inspector.listed_directories, ['/fixture']);
    });

    test('preserves incomplete SDK observations', () async {
      final apps = _entry('/fixture/apps', FilesystemEntryKind.directory);
      final blocked = TargetPath('/fixture/blocked');

      final inspector = _ExplorerInspector(
        children: {
          '/fixture': [apps.path, blocked],
        },
        entries: _entry_map([apps]),
        inspection_failures: {
          blocked.value: TargetInspectionException(
            code: TargetInspectionErrorCode.permissionDenied,
            operation: TargetInspectionOperation.inspect,
            path: blocked,
            message: 'Permission denied.',
          ),
        },
      );

      final controller = _controller(inspector);

      final model = await controller.start();

      expect(model.is_incomplete, isTrue);
      expect(model.listing.is_complete, isFalse);
      expect(model.listing.issues, hasLength(1));
      expect(
        model.listing.issues.single.code,
        TargetInspectionErrorCode.permissionDenied,
      );

      // Successfully observed directories remain browsable.
      // This does not make the incomplete listing authoritative.
      final child = await controller.open_selected();

      expect(child.current_directory.value, '/fixture/apps');
      expect(
        inspector.listed_directories,
        orderedEquals(['/fixture', '/fixture/apps']),
      );
    });

    test('does not commit navigation after unexpected SDK errors', () async {
      final apps = _entry('/fixture/apps', FilesystemEntryKind.directory);

      final inspector = _ExplorerInspector(
        children: {
          '/fixture': [apps.path],
        },
        entries: _entry_map([apps]),
      );

      final controller = _controller(inspector);

      final before = await controller.start();

      inspector.unexpected_directory = '/fixture/apps';

      await expectLater(controller.open_selected(), throwsA(isA<StateError>()));

      expect(identical(controller.model, before), isTrue);
      expect(controller.model?.history, isEmpty);
      expect(controller.is_loading, isFalse);
    });

    test('preserves navigation state when back inspection fails', () async {
      final apps = _entry('/fixture/apps', FilesystemEntryKind.directory);

      final inspector = _ExplorerInspector(
        children: {
          '/fixture': [apps.path],
        },
        entries: _entry_map([apps]),
      );

      final controller = _controller(inspector);

      await controller.start();
      final child = await controller.open_selected();

      inspector.unexpected_directory = '/fixture';

      await expectLater(controller.back(), throwsA(isA<StateError>()));

      expect(identical(controller.model, child), isTrue);
      expect(controller.model?.history, hasLength(1));

      inspector.unexpected_directory = null;

      final root = await controller.back();

      expect(root.current_directory.value, '/fixture');
      expect(root.history, isEmpty);
    });

    test('preserves Windows-native paths unchanged', () async {
      const root = r'C:\workspace';
      const child_path = r'C:\workspace\src';

      final directory = _entry(child_path, FilesystemEntryKind.directory);

      final inspector = _ExplorerInspector(
        children: {
          root: [directory.path],
        },
        entries: _entry_map([directory]),
      );

      final controller = _controller(inspector, root: root);

      await controller.start();
      final child = await controller.open_selected();

      expect(child.current_directory.value, child_path);
      expect(inspector.listed_directories, orderedEquals([root, child_path]));

      await controller.back();

      expect(controller.model?.current_directory.value, root);
    });

    test('rejects overlapping inspection requests', () async {
      final gate = Completer<void>();

      final inspector = _ExplorerInspector(inspection_gate: gate);

      final controller = _controller(inspector);

      final pending_start = controller.start();

      expect(controller.is_loading, isTrue);

      await expectLater(controller.start(), throwsA(isA<StateError>()));

      expect(() => controller.move_selection(1), throwsStateError);

      expect(() => controller.quit(), throwsStateError);

      gate.complete();

      final model = await pending_start;

      expect(model.current_directory.value, '/fixture');
      expect(controller.is_loading, isFalse);
    });

    test('quit closes interaction without filesystem changes', () async {
      final inspector = _ExplorerInspector();
      final controller = _controller(inspector);

      expect(() => controller.move_selection(1), throwsStateError);

      await controller.start();

      final closed = controller.quit();

      expect(closed.is_closed, isTrue);
      expect(inspector.listed_directories, ['/fixture']);

      expect(() => controller.move_selection(1), throwsStateError);

      await expectLater(controller.open_selected(), throwsStateError);

      await expectLater(controller.back(), throwsStateError);

      await expectLater(controller.start(), throwsStateError);
    });
  });
}

/// Creates a filesystem entry without native inspection.
FilesystemEntry _entry(String path, FilesystemEntryKind kind) {
  return FilesystemEntry(
    path: TargetPath(path),
    kind: kind,
    metadata: FilesystemMetadata(),
  );
}

/// Indexes test observations by their unchanged target paths.
Map<String, FilesystemEntry> _entry_map(List<FilesystemEntry> entries) {
  return {for (final entry in entries) entry.path.value: entry};
}

/// Creates an explorer with an isolated SDK instance.
ExplorerController _controller(
  TargetInspector inspector, {
  String root = '/fixture',
}) {
  return ExplorerController(
    sdk: RudraSdk(target_id: 'fixture-target', inspector: inspector),
    starting_directory: TargetPath(root),
  );
}

/// A deterministic read-only inspector for explorer tests.
///
/// All observations are explicitly configured in memory.
/// Only the TargetInspector read-only contract is implemented.
final class _ExplorerInspector implements TargetInspector {
  /// Creates a filesystem observation fixture.
  ///
  /// [inspection_gate] can delay enumeration to test concurrency.
  _ExplorerInspector({
    Map<String, List<TargetPath>> children = const {},
    Map<String, FilesystemEntry> entries = const {},
    Map<String, TargetInspectionException> inspection_failures = const {},
    this.inspection_gate,
  }) : _children = children,
       _entries = entries,
       _inspection_failures = inspection_failures;

  /// Child paths indexed by their parent directory.
  final Map<String, List<TargetPath>> _children;

  /// Successfully inspectable entries indexed by path.
  final Map<String, FilesystemEntry> _entries;

  /// Typed entry inspection failures indexed by path.
  final Map<String, TargetInspectionException> _inspection_failures;

  /// Optional gate for testing overlapping operations.
  final Completer<void>? inspection_gate;

  /// Directory for which enumeration should fail unexpectedly.
  String? unexpected_directory;

  /// Recorded directory enumeration requests.
  final List<String> listed_directories = [];

  /// Recorded entry inspection requests.
  final List<String> inspected_paths = [];

  /// Number of symbolic-link destination read attempts.
  int symbolic_link_calls = 0;

  /// Emits only configured directory children.
  @override
  Stream<TargetPath> list_directory(TargetPath path) async* {
    listed_directories.add(path.value);

    if (inspection_gate != null) {
      await inspection_gate!.future;
    }

    if (unexpected_directory == path.value) {
      throw StateError('Injected inspection failure: ${path.value}');
    }

    for (final child in _children[path.value] ?? const <TargetPath>[]) {
      yield child;
    }
  }

  /// Returns configured observations or typed failures.
  @override
  Future<FilesystemEntry> inspect(TargetPath path) async {
    inspected_paths.add(path.value);

    final failure = _inspection_failures[path.value];

    if (failure != null) {
      throw failure;
    }

    final entry = _entries[path.value];

    if (entry == null) {
      throw StateError('Unconfigured entry inspection: ${path.value}');
    }

    return entry;
  }

  /// Rejects unexpected capability discovery.
  @override
  Future<TargetCapabilities> capabilities_for(TargetPath path) async {
    throw StateError('Unexpected capability request: ${path.value}');
  }

  /// Rejects symbolic-link destination resolution.
  @override
  Future<TargetPath> read_symbolic_link(TargetPath path) async {
    symbolic_link_calls++;

    throw StateError('Unexpected link resolution: ${path.value}');
  }
}
