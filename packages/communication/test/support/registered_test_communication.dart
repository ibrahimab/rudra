import 'package:rudra_communication/rudra_communication.dart';

/// Configures a communication lifecycle for the supplied controlled transports.
///
/// Each fixture is registered and explicitly enabled in list order.
Communication registered_test_communication(
  List<Transport> transports, {
  MessageCodecRegistry? codecs,
  RequestHandlerRegistry? handlers,
  MessageSessionOptions options = const MessageSessionOptions(),
}) {
  final endpoints = [
    for (final index in Iterable<int>.generate(transports.length))
      TransportEndpoint(transport_id: 'test-$index'),
  ];
  return Communication(
    transport_configuration: TransportConfiguration.enabled(endpoints),
    transport_registry: TransportRegistry([
      for (final (index, transport) in transports.indexed)
        (
          id: endpoints[index].transport_id,
          default_platform: null,
          create: (_) => transport,
        ),
    ]),
    codecs: codecs,
    handlers: handlers,
    options: options,
  );
}
