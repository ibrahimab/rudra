/// Public API of Rudra's modular command-line framework.
///
/// The framework manages module registration, command execution,
/// and application-owned process exit statuses.
///
/// Packages implementing filesystem functionality must remain
/// independent of this library. Their CLI integration belongs
/// in application-level adapter modules.
///
/// Production applications register product modules only.
/// Development applications register product modules and
/// additional development modules.
library;

export 'src/rudra_cli.dart' show RudraCli;
export 'src/core/cli/rudra_cli_module.dart' show RudraCliModule;
export 'src/core/cli/rudra_exit_code.dart' show RudraExitCode;
