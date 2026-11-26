import 'package:rudra_cli/rudra_cli.dart';
import 'package:rudra_cli/src/features/host/cli/host_cli_module.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies presentation of an occupied host persistence scope.
///
/// The injected application operation rejects ownership without
/// performing native locking or accessing persistence.
void main() {
  test('ownership conflict returns the typed host exit status', () async {
    final output = StringBuffer();
    final errors = StringBuffer();

    final cli = RudraCli(error_output: errors);

    cli.register_module(
      HostCliModule(
        run_host: ({required on_ready}) async {
          throw const HostAlreadyOwnedException(os_user_id: 'test-owner');
        },
        output: output,
        error_output: errors,
      ),
    );

    final status = await cli.run(['host', 'start', '--foreground']);

    expect(status, RudraExitCode.host_conflict.value);

    expect(errors.toString(), contains('Rudra Host already running'));

    expect(errors.toString(), contains('test-owner'));

    // Ownership rejection must never be presented as successful
    // initialization or graceful host completion.
    expect(output.toString(), isNot(contains('Host ready')));
    expect(output.toString(), isNot(contains('Host stopped')));
  });
}
