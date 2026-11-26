import 'package:args/command_runner.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import '../../../core/cli/rudra_exit_code.dart';
import '../../../core/rendering/renderer.dart';

import '../presentation/directory_listing_presenter.dart';
import '../presentation/filesystem_view_model.dart';
import '../presentation/widgets/directory_listing/directory_listing_view_model.dart';

/// Lists the immediate children of a filesystem directory.
///
/// ListCommand coordinates one read-only filesystem listing.
///
/// Responsibilities:
/// - Validate command arguments.
/// - Select the requested target-native directory.
/// - Request observations through RudraSdk.filesystem.
/// - Prepare presentation data through DirectoryListingPresenter.
/// - Delegate display to an injected Renderer.
/// - Return a typed CLI exit code.
///
/// The command does not know which rendering backend is used.
///
/// It never:
/// - Inspects native filesystem entries directly.
/// - Follows symbolic links.
/// - Generates terminal escape sequences.
/// - Writes directly to stdout or stderr.
/// - Creates or executes cleanup sessions.
/// - Modifies filesystem content.
///
/// Example:
/// ```dart
/// final command = ListCommand(
///   connect: connect_sdk,
///   working_directory: TargetPath('/workspace'),
///   renderer: renderer,
/// );
/// ```
///
/// CLI usage:
/// ```text
/// rudra ls
/// rudra ls /absolute/directory
/// ```
final class ListCommand extends Command<int> {
  /// Creates a read-only filesystem listing command.
  ///
  /// [connect] provides the configured filesystem service.
  ///
  /// [working_directory] is the default target-native directory
  /// when no explicit directory argument is supplied.
  ///
  /// [renderer] receives the prepared [FilesystemViewModel].
  /// Its concrete implementation determines how directory rows
  /// and inspection diagnostics are displayed.
  ///
  /// [presenter] prepares SDK observations for the compact
  /// directory listing layout.
  ///
  /// The SDK and working directory must describe the same
  /// configured filesystem target.
  ///
  /// Construction performs no filesystem inspection or
  /// terminal I/O.
  ListCommand({
    required Future<RudraSdk> Function() connect,
    required TargetPath working_directory,
    required Renderer<FilesystemViewModel> renderer,
    DirectoryListingPresenter presenter = const DirectoryListingPresenter(),
  }) : _connect = connect,
       _working_directory = working_directory,
       _renderer = renderer,
       _presenter = presenter;

  /// Command identifier used by the CLI argument parser.
  @override
  String get name => 'ls';

  /// Description displayed by CLI help.
  @override
  String get description =>
      'List the immediate children of a filesystem directory.';

  /// Command invocation displayed by CLI help.
  @override
  String get invocation => 'rudra ls [absolute-directory]';

  /// SDK providing platform-independent filesystem operations.
  final Future<RudraSdk> Function() _connect;

  /// Default target-native directory for the command.
  final TargetPath _working_directory;

  /// Backend-independent presentation renderer.
  final Renderer<FilesystemViewModel> _renderer;

  /// Converts SDK observations into presentation-ready data.
  final DirectoryListingPresenter _presenter;

  /// Lists and renders the requested directory.
  ///
  /// Accepts zero or one positional directory argument.
  ///
  /// With no argument, the injected working directory is used.
  ///
  /// Explicit paths retain their original target-native
  /// spelling and are passed to the SDK for validation.
  ///
  /// The presenter uses DirectoryListingLayout.compact,
  /// preserving SDK observation ordering and the established
  /// TYPE, LOGICAL_BYTES, PATH output contract.
  ///
  /// Incomplete observations retain successfully inspected
  /// entries and their typed inspection issues.
  ///
  /// Returns:
  /// - RudraExitCode.success for complete observations.
  /// - RudraExitCode.inspection_incomplete for partial results.
  ///
  /// Invalid argument counts and empty explicit arguments
  /// produce a UsageException.
  ///
  /// Unexpected SDK, presenter, and renderer exceptions
  /// propagate to the caller.
  ///
  /// No filesystem modification is performed.
  @override
  Future<int> run() async {
    final arguments = argResults?.rest ?? const <String>[];

    if (arguments.length > 1) {
      throw UsageException('Expected at most one directory argument.', usage);
    }

    if (arguments.isNotEmpty && arguments.single.isEmpty) {
      throw UsageException('The directory argument must not be empty.', usage);
    }

    TargetPath directory = _working_directory;
    if (arguments.isNotEmpty) {
      try {
        directory = TargetPath(arguments.single);
      } on ArgumentError {
        throw UsageException('Invalid directory argument.', usage);
      }
    }

    // Only the SDK performs filesystem inspection.
    final sdk = await _connect();
    final listing = await sdk.filesystem.list(directory: directory);

    // Preserve the established compact listing format.
    final view_model = _presenter.present(
      listing,
      layout: DirectoryListingLayout.compact,
    );

    // Rendering and diagnostic output belong to the
    // injected backend, not the command.
    _renderer.render(view_model);

    return listing.is_complete
        ? RudraExitCode.success.value
        : RudraExitCode.inspection_incomplete.value;
  }
}
