import 'package:rudra_cli/src/features/explorer/application/explorer_action_registry.dart';
import 'package:rudra_cli/src/features/explorer/application/explorer_model.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Tests action registration and physical-key dispatch using
/// synthetic action implementations.
void main() {
  group('ExplorerActionRegistry', () {
    test('resolves shortcuts case-insensitively', () {
      final action = _RecordingAction(id: 'fixture.inspect', shortcut: 'p');

      final registry = ExplorerActionRegistry([
        ExplorerFeatureContribution(id: 'fixture', actions: [action]),
      ]);

      expect(registry.resolve('p'), same(action));
      expect(registry.resolve('P'), same(action));
      expect(registry.resolve('x'), isNull);
    });

    test('does not execute actions during registration', () {
      var executions = 0;

      final registry = ExplorerActionRegistry([
        ExplorerFeatureContribution(
          id: 'fixture',
          actions: [
            _RecordingAction(
              id: 'fixture.inspect',
              shortcut: 'i',
              on_execute: (_) => executions++,
            ),
          ],
        ),
      ]);

      expect(executions, 0);
      expect(registry.resolve('i'), isNotNull);
      expect(executions, 0);
    });

    test('dispatches the current navigation snapshot', () async {
      ExplorerModel? received;

      final registry = ExplorerActionRegistry([
        ExplorerFeatureContribution(
          id: 'fixture',
          actions: [
            _RecordingAction(
              id: 'fixture.inspect',
              shortcut: 'i',
              on_execute: (model) => received = model,
            ),
          ],
        ),
      ]);

      final explorer = _explorer();

      await registry.resolve('I')!.execute(explorer);

      expect(received, same(explorer));
      expect(received!.current_directory.value, '/fixture');
    });

    test('defensively copies feature contributions', () {
      final original = <ExplorerAction>[
        _RecordingAction(id: 'fixture.inspect', shortcut: 'i'),
      ];

      final contribution = ExplorerFeatureContribution(
        id: 'fixture',
        actions: original,
      );

      original.clear();

      expect(contribution.actions, hasLength(1));
      expect(() => contribution.actions.clear(), throwsUnsupportedError);
    });

    test('rejects blank and duplicate feature identifiers', () {
      expect(
        () => ExplorerActionRegistry([ExplorerFeatureContribution(id: ' ')]),
        throwsArgumentError,
      );

      expect(
        () => ExplorerActionRegistry([
          ExplorerFeatureContribution(id: 'fixture'),
          ExplorerFeatureContribution(id: 'fixture'),
        ]),
        throwsArgumentError,
      );
    });

    test('rejects duplicate action identifiers across features', () {
      expect(
        () => ExplorerActionRegistry([
          ExplorerFeatureContribution(
            id: 'first',
            actions: [_RecordingAction(id: 'shared.action', shortcut: 'a')],
          ),
          ExplorerFeatureContribution(
            id: 'second',
            actions: [_RecordingAction(id: 'shared.action', shortcut: 'b')],
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('rejects blank action identifiers', () {
      expect(
        () => ExplorerActionRegistry([
          ExplorerFeatureContribution(
            id: 'fixture',
            actions: [_RecordingAction(id: ' ', shortcut: 'i')],
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('rejects shortcuts that collide ignoring case', () {
      expect(
        () => ExplorerActionRegistry([
          ExplorerFeatureContribution(
            id: 'fixture',
            actions: [
              _RecordingAction(id: 'fixture.one', shortcut: 'p'),
              _RecordingAction(id: 'fixture.two', shortcut: 'P'),
            ],
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('reserves Quit regardless of case', () {
      for (final shortcut in ['q', 'Q']) {
        expect(
          () => ExplorerActionRegistry([
            ExplorerFeatureContribution(
              id: 'fixture',
              actions: [
                _RecordingAction(id: 'fixture.quit', shortcut: shortcut),
              ],
            ),
          ]),
          throwsArgumentError,
        );
      }
    });

    test('rejects unsupported shortcut representations', () {
      for (final shortcut in ['', ' ', 'ab', '\n', 'é']) {
        expect(
          () => ExplorerActionRegistry([
            ExplorerFeatureContribution(
              id: 'fixture',
              actions: [
                _RecordingAction(id: 'fixture.invalid', shortcut: shortcut),
              ],
            ),
          ]),
          throwsArgumentError,
        );
      }
    });

    test('propagates action failures during execution', () async {
      final registry = ExplorerActionRegistry([
        ExplorerFeatureContribution(
          id: 'fixture',
          actions: [
            _RecordingAction(
              id: 'fixture.failure',
              shortcut: 'f',
              on_execute: (_) {
                throw StateError('Injected failure.');
              },
            ),
          ],
        ),
      ]);

      await expectLater(
        registry.resolve('f')!.execute(_explorer()),
        throwsStateError,
      );
    });
  });
}

/// Synthetic action implementation used by registry tests.
///
/// [on_execute] records or fails execution when supplied.
final class _RecordingAction implements ExplorerAction {
  /// Creates a synthetic keyboard action.
  ///
  /// [id] identifies the registered action.
  ///
  /// [shortcut] supplies its printable keyboard binding.
  ///
  /// [on_execute] optionally observes action execution.
  const _RecordingAction({
    required this.id,
    required this.shortcut,
    this.on_execute,
  });

  /// Unique action identifier.
  @override
  final String id;

  /// Keyboard shortcut.
  @override
  final String shortcut;

  /// Optional execution callback for test assertions.
  final void Function(ExplorerModel)? on_execute;

  /// Executes the synthetic action.
  ///
  /// [model] is the navigation snapshot passed by the caller.
  ///
  /// Exceptions from [on_execute] propagate to the caller.
  @override
  Future<void> execute(ExplorerModel model) async {
    on_execute?.call(model);
  }
}

/// Creates an Explorer navigation snapshot entirely in memory.
ExplorerModel _explorer() {
  final root = TargetPath('/fixture');

  return ExplorerModel(
    root_directory: root,
    listing: DirectoryListing(
      target_id: 'fixture-target',
      directory: root,
      entries: const [],
      is_complete: true,
    ),
  );
}
