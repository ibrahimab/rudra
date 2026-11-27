/// Portable host lifecycle and platform capability contracts.
///
/// Exposes host orchestration and the contracts implemented
/// by native host adapters.
library;

/// Trusted operating-system identity resolution.
export 'platform/contracts/host_identity_provider.dart';

/// Exclusive host persistence ownership contracts.
export 'platform/contracts/host_ownership_provider.dart';
export 'platform/contracts/host_ownership_lease.dart';

/// Optional host platform capability contributions.
export 'plugins/host_platform_plugin.dart';
export 'plugins/host_platform_registry.dart';

/// Explicit host installation contracts and orchestration.
export 'install/host_install_step.dart';
export 'install/host_install_registry.dart';
export 'install/host_install_plan.dart';
export 'install/host_install_result.dart';
export 'install/host_installer.dart';

/// Portable host execution lifecycle.
export 'runtime/rudra_host.dart';

/// Authoritative filesystem inspection application.
export '../filesystem/application/filesystem_application.dart';
export '../filesystem/application/filesystem_observation.dart';
