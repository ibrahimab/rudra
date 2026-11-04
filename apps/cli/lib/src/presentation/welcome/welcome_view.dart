import '../filesystem/directory_listing_view.dart';
import 'welcome_model.dart';

/// Renders the CLI welcome screen.
///
/// All information is supplied through [WelcomeModel].
/// The view performs no filesystem inspection or mutation.
final class WelcomeView {
  /// Creates a stateless terminal welcome view.
  const WelcomeView();

  /// Renders the welcome screen and any available directory data.
  ///
  /// [output] receives the presentation.
  /// [error_output] receives typed inspection diagnostics.
  ///
  /// No input handling, session operations, or cleanup occurs.
  void render(
    WelcomeModel model, {
    required StringSink output,
    StringSink? error_output,
  }) {
    output.writeln();
    output.writeln('RUDRA  |  READ ONLY');
    output.writeln('Read-only filesystem exploration.');
    output.writeln();

    if (model.can_inspect) {
      output.writeln('Target: ${model.target_id}');
      output.writeln(
        'Starting directory: ${model.starting_directory!.value}',
      );
      output.writeln();

      final listing = model.listing;

      if (listing != null) {
        const listing_view = DirectoryListingView();

        listing_view.render_detailed(
          listing,
          output: output,
        );

        if (error_output != null) {
          listing_view.render_issues(
            listing,
            output: error_output,
          );
        }

        output.writeln();
      }
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
