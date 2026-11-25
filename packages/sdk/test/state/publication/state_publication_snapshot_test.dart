import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

void main() {
  final state = RudraState(workflows: WorkflowsState(current_workflow: null));

  test('retains publication metadata and immutable application state', () {
    final snapshot = StatePublicationSnapshot(
      generation: 'generation-a',
      revision: 1,
      state: state,
    );

    expect(snapshot.generation, 'generation-a');
    expect(snapshot.revision, 1);
    expect(snapshot.state, same(state));
  });

  test('rejects blank publication generations', () {
    expect(
      () =>
          StatePublicationSnapshot(generation: ' ', revision: 1, state: state),
      throwsArgumentError,
    );
  });

  test('rejects non-positive publication revisions', () {
    for (final revision in [0, -1]) {
      expect(
        () => StatePublicationSnapshot(
          generation: 'generation-a',
          revision: revision,
          state: state,
        ),
        throwsArgumentError,
      );
    }
  });
}
