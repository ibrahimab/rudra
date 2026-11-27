import 'dart:io';

import 'package:rudra_cli/rudra_cli.dart';
import 'package:rudra_cli/rudra_product_cli.dart';
import 'package:rudra_cli/src/features/host/cli/host_cli_module.dart';
import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_host/rudra_host.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_target_inspection/rudra_target_inspection.dart';

/// Runs normal CLI commands with isolated native resources supplied by tests.
///
/// The production host entrypoint continues to resolve its installed paths.
Future<void> main(List<String> arguments) async {
  final runtime = arguments[0];
  final database = File(arguments[1]);
  final transport = MacOsUnixTransport(socket_path: arguments[2]);
  final commands = arguments.sublist(3);

  if (commands.first == 'host') {
    final cli = RudraCli();
    cli.register_module(
      HostCliModule(
        run_host: ({required on_ready}) async {
          final host = HostComposition(
            identity_provider: const MacOsHostIdentity(),
            ownership_provider: MacOsHostOwnershipProvider(
              runtime_directory: runtime,
            ),
            resolve_database: () => database,
            target_id: 'fixture-filesystem',
            inspector: MacOsTargetInspector(),
            transport_configuration: TransportConfiguration.enabled([
              MacOsUnixTransport.endpoint(socket_path: arguments[2]),
            ]),
          );

          await const MacOsHostShutdown().run(
            (shutdown) => host.run(shutdown: shutdown, on_ready: on_ready),
          );
        },
        output: stdout,
        error_output: stderr,
      ),
    );
    exitCode = await cli.run(commands);
    return;
  }

  final cli = compose_product_cli(
    sdk_composition: ProductSdkComposition(
      sdk: RudraSdk(),
      working_directory: TargetPath(runtime),
      connection_params: ConnectionParams(transport: transport),
    ),
  );
  exitCode = await cli.run(commands);
}
