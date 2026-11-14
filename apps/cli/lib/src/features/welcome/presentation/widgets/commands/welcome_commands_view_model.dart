/// Immutable presentation configuration for Welcome commands.
///
/// This component controls whether filesystem-specific command
/// hints should be displayed.
///
/// It does not register commands, parse arguments, invoke SDK
/// operations, or determine platform support.
///
/// Command registration remains owned by RudraCli.
///
/// Example:
/// ```dart
/// const model = WelcomeCommandsViewModel(
///   show_filesystem_commands: true,
/// );
/// ```
final class WelcomeCommandsViewModel {
  /// Creates a command-hint presentation.
  const WelcomeCommandsViewModel({required this.show_filesystem_commands});

  /// Whether filesystem commands should appear in the hints.
  final bool show_filesystem_commands;
}
