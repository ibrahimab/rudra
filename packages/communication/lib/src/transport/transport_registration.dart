import 'contracts/transport.dart';

/// Registers one available transport implementation and its default platform.
///
/// [id] is a unique implementation key.
/// [default_platform] is the value of `Platform.operatingSystem` where this
/// transport is selected by default, or null for explicit activation.
/// [create] constructs an inactive transport from endpoint options.
/// The factory must acquire no resources and validate the options it accepts.
typedef TransportRegistration = ({
  String id,
  String? default_platform,
  Transport Function(Map<String, String> options) create,
});
