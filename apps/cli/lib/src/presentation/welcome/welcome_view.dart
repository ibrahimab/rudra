import 'welcome_model.dart';

/// Renders Rudra's CLI welcome screen.
///
/// WelcomeView is responsible only for terminal presentation.
///
/// It does not:
/// - Construct or invoke SDK services.
/// - Inspect the filesystem.
/// - Manage inspection sessions.
/// - Read user input.
/// - Navigate between screens.
/// - Execute cleanup operations.
///
/// A controller will supply the [WelcomeModel] and determine
/// when this view should be rendered.
///
/// Output is written to an explicitly supplied [StringSink],
/// making the view independently testable.
///
/// Example:
/// ```dart
/// final view = WelcomeView();
/// final output = StringBuffer();
///
/// view.render(
///   WelcomeModel(product_name: 'Rudra'),
///   output: output,
/// );
///
/// print(output.toString());
/// ```
final class WelcomeView {
  /// Creates a stateless terminal welcome view.
  ///
  /// Construction performs no input/output operations.
  const WelcomeView();

  /// Renders the welcome screen using [model].
  ///
  /// [output] receives the complete textual presentation.
  ///
  /// The view displays filesystem inspection commands only
  /// when [WelcomeModel.can_inspect] is true.
  ///
  /// A configured target does not guarantee that inspection
  /// will succeed; errors remain the SDK's responsibility.
  ///
  /// No filesystem access, terminal input, or cleanup occurs.
  ///
  /// Example:
  /// ```dart
  /// const view = WelcomeView();
  ///
  /// view.render(
  ///   WelcomeModel(
  ///     product_name: 'Rudra',
  ///     target_id: 'local-macos',
  ///     starting_directory: TargetPath('/Users/example'),
  ///   ),
  ///   output: stdout,
  /// );
  /// ```
  void render(
    WelcomeModel model, {
    required StringSink output,
  }) {
    output.writeln(model.product_name);
    output.writeln('Read-only filesystem exploration.');
    output.writeln();

    if (model.can_inspect) {
      output.writeln('Target: ${model.target_id}');
      output.writeln(
        'Starting directory: ${model.starting_directory!.value}',
      );
      output.writeln();
    } else {
      output.writeln(
        'Filesystem inspection is not available '
        'for the current target.',
      );
      output.writeln();
    }

    output.writeln('Available commands:');

    if (model.can_inspect) {
      output.writeln(
        '  rudra ls                  Inspect the starting directory',
      );
      output.writeln(
        '  rudra ls /absolute/path   Inspect another directory',
      );
    }

    output.writeln(
      '  rudra about               Show application information',
    );
    output.writeln(
      '  rudra --help              Show available commands',
    );
    output.writeln();
    output.writeln(
      'Inspection never authorizes file modification or deletion.',
    );
  }
}
