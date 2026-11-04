import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import '../rudra_exit_code.dart';

/// Lists the immediate children of a filesystem directory.
///
/// ListCommand is a CLI presentation adapter for Rudra's
/// platform-independent filesystem service.
///
/// It parses command arguments, invokes the SDK, renders
/// standardized results, and maps the outcome to a CLI exit code.
///
/// It does not enumerate directories or inspect files directly.
///
/// All filesystem observations are performed through
/// [RudraSdk.filesystem].
///
/// The command is read-only and does not create sessions,
/// mark cleanup candidates, or authorize filesystem mutations.
///
/// Example:
/// ```dart
/// final command = ListCommand(
///   sdk: sdk,
///   working_directory: TargetPath('/Users/example'),
/// );
/// ```
///
/// CLI usage:
/// ```text
/// rudra ls
/// rudra ls /Users/example/Downloads
/// ```
final class ListCommand extends Command<int> {
  /// Creates a filesystem listing command.
  ///
  /// [sdk] provides the configured filesystem service.
  ///
  /// [working_directory] is the default target-native directory
  /// used when no explicit path is provided.
  ///
  /// The application composition boundary must supply a working
  /// directory that belongs to the SDK's configured target.
  ///
  /// [output] receives successful filesystem observations.
  /// It defaults to stdout.
  ///
  /// [error_output] receives inspection issues.
  /// It defaults to stderr.
  ///
  /// Construction does not inspect or modify filesystem content.
  ListCommand({
    required RudraSdk sdk,
    required TargetPath working_directory,
    StringSink? output,
    StringSink? error_output,
  })  : _sdk = sdk,
        _working_directory = working_directory,
        _output = output ?? stdout,
        _error_output = error_output ?? stderr;

  /// Command identifier used by Rudra's argument parser.
  @override
  String get name => 'ls';

  /// Description displayed in CLI help.
  @override
  String get description =>
      'List the immediate children of a filesystem directory.';

  /// Command invocation displayed in CLI help.
  ///
  /// The directory argument is optional and must currently
  /// be an absolute path in the target's native syntax.
  @override
  String get invocation => 'rudra ls [absolute-directory]';

  /// SDK providing platform-independent filesystem operations.
  final RudraSdk _sdk;

  /// Default directory supplied by application composition.
  final TargetPath _working_directory;

  /// Destination for successfully inspected filesystem entries.
  final StringSink _output;

  /// Destination for inspection issues and incomplete results.
  final StringSink _error_output;

  /// Executes the filesystem listing command.
  ///
  /// Accepts zero or one positional directory argument.
  ///
  /// When the argument is omitted, the injected working directory
  /// is used without attempting host-specific path resolution.
  ///
  /// Explicit relative paths are not resolved by this command.
  /// They are passed to the SDK, whose target inspector requires
  /// an absolute target-native path.
  ///
  /// Directory entries are rendered using their observed type,
  /// logical size in bytes, and original target-native path.
  ///
  /// Unknown logical sizes are displayed as '?' rather than zero.
  ///
  /// Inspection issues are written to [stderr] through the
  /// configured error output sink.
  ///
  /// Returns:
  /// - [RudraExitCode.success] for a complete listing.
  /// - [RudraExitCode.inspection_incomplete] for partial results.
  ///
  /// Invalid argument counts produce a [UsageException].
  ///
  /// Unexpected SDK failures are allowed to propagate.
  ///
  /// No filesystem mutation is performed.
  @override
  Future<int> run() async {
    final arguments = argResults?.rest ?? const <String>[];

    if (arguments.length > 1) {
      throw UsageException(
        'Expected at most one directory argument.',
        usage,
      );
    }

    if (arguments.isNotEmpty && arguments.single.isEmpty) {
      throw UsageException(
        'The directory argument must not be empty.',
        usage,
      );
    }

    final directory =
        arguments.isEmpty ? _working_directory : TargetPath(arguments.single);

    final listing = await _sdk.filesystem.list(
      directory: directory,
    );

    // Presentation formatting belongs to the CLI.
    // The SDK returns standardized, unformatted data.
    _output.writeln('TYPE\tLOGICAL_BYTES\tPATH');

    for (final entry in listing.entries) {
      final entry_type = entry.kind.name;

      // Unknown size must never be represented as zero.
      final logical_size = entry.metadata.logical_size_bytes?.toString() ?? '?';

      _output.writeln(
        '$entry_type\t$logical_size\t${entry.path.value}',
      );
    }

    // Preserve successful observations while making every
    // reported inspection failure visible to the user.
    for (final issue in listing.issues) {
      _error_output.writeln(
        '${issue.operation.name}: '
        '${issue.code.name}: '
        '${issue.path.value}: '
        '${issue.message}',
      );
    }

    if (!listing.is_complete) {
      // An incomplete result is possible without an issue when
      // collection was intentionally stopped before completion.
      if (listing.issues.isEmpty) {
        _error_output.writeln(
          'Filesystem inspection did not complete.',
        );
      }

      return RudraExitCode.inspection_incomplete.value;
    }

    return RudraExitCode.success.value;
  }
}
