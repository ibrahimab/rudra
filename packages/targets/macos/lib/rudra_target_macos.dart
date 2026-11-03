/// Read-only macOS filesystem inspection support for Rudra.
///
/// This package translates Darwin filesystem observations into
/// platform-independent Rudra target contracts.
///
/// Platform-specific native details remain internal to the adapter.
/// No filesystem mutation or cleanup execution is provided.
///
/// The adapter is being introduced incrementally. Until every
/// TargetInspector operation is implemented, it must not be used
/// as a complete target adapter in application composition.
library;

export 'src/mac_os_target_inspector.dart';
