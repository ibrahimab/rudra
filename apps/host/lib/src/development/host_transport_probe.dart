import 'dart:typed_data';

import 'package:rudra_sdk/rudra_sdk.dart';

/// Request byte recognized by the development transport probe.
const int _ping = 0x01;

/// Response byte returned for a recognized probe request.
const int _pong = 0x02;

/// Executes a development-only byte exchange on [connection].
///
/// Responds to each recognized request byte independently,
/// preserving correctness when transport chunks contain multiple
/// requests or arrive across separate stream events.
///
/// Returns when the peer disconnects or supplies an unsupported
/// byte. Transport failures propagate to the session coordinator.
///
/// No workflow operation or persistence access occurs.
///
/// Example:
/// ```dart
/// await run_host_transport_probe(connection);
/// ```
Future<void> run_host_transport_probe(HostConnection connection) async {
  await for (final chunk in connection.incoming) {
    for (final byte in chunk) {
      // Interpret individual bytes rather than assuming that
      // native stream events correspond to request boundaries.
      if (byte != _ping) {
        return;
      }

      await connection.send(Uint8List.fromList([_pong]));
    }
  }
}
