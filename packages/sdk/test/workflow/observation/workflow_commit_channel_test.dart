import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies committed-change notification independently of persistence.
void main() {
  group('LocalWorkflowCommitChannel', () {
    test('publishes to multiple subscribers of the same owner', () async {
      final channel = LocalWorkflowCommitChannel();
      var first_count = 0;
      var second_count = 0;

      final first = channel
          .watch(os_user_id: 'owner-a')
          .listen((_) => first_count++);

      final second = channel
          .watch(os_user_id: 'owner-a')
          .listen((_) => second_count++);

      channel.publish(os_user_id: 'owner-a');

      await Future<void>.delayed(Duration.zero);

      expect(first_count, 1);
      expect(second_count, 1);

      await first.cancel();
      await second.cancel();
      await channel.close();
    });

    test('isolates notifications by trusted owner', () async {
      final channel = LocalWorkflowCommitChannel();
      var owner_a_count = 0;
      var owner_b_count = 0;

      final owner_a = channel
          .watch(os_user_id: 'owner-a')
          .listen((_) => owner_a_count++);

      final owner_b = channel
          .watch(os_user_id: 'owner-b')
          .listen((_) => owner_b_count++);

      channel.publish(os_user_id: 'owner-a');

      await Future<void>.delayed(Duration.zero);

      expect(owner_a_count, 1);
      expect(owner_b_count, 0);

      await owner_a.cancel();
      await owner_b.cancel();
      await channel.close();
    });

    test('does not replay notifications to late subscribers', () async {
      final channel = LocalWorkflowCommitChannel();

      channel.publish(os_user_id: 'owner-a');

      var received = 0;
      final subscription = channel
          .watch(os_user_id: 'owner-a')
          .listen((_) => received++);

      await Future<void>.delayed(Duration.zero);

      expect(received, 0);

      await subscription.cancel();
      await channel.close();
    });

    test('completes subscriptions when closed', () async {
      final channel = LocalWorkflowCommitChannel();

      final completion = channel.watch(os_user_id: 'owner-a').toList();

      await channel.close();

      expect(await completion, isEmpty);
      expect(() => channel.publish(os_user_id: 'owner-a'), returnsNormally);
    });

    test('rejects blank trusted owner identifiers', () async {
      final channel = LocalWorkflowCommitChannel();

      expect(() => channel.watch(os_user_id: ' '), throwsArgumentError);
      expect(() => channel.publish(os_user_id: ''), throwsArgumentError);

      await channel.close();
    });
  });
}
