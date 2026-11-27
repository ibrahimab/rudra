import 'dart:io';

import 'package:rudra_communication/rudra_communication.dart';

/// Substitutes [transport] as the native default for one isolated lifecycle.
TransportRegistry host_test_transport_registry(Transport transport) =>
    TransportRegistry([
      (
        id: 'host-fixture',
        default_platform: Platform.operatingSystem,
        create: (_) => transport,
      ),
    ]);
