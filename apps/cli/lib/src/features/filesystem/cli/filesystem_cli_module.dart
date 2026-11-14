import 'package:args/command_runner.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import '../../../core/cli/rudra_cli_module.dart';
import '../../../core/rendering/renderer.dart';

import '../presentation/filesystem_view_model.dart';
import 'list_command.dart';

/// Registers SDK-backed filesystem commands for Rudra.
///
/// FilesystemCliModule is a CLI application-composition component.
///
/// It receives a configured SDK, a target-native working directory,
/// and a renderer selected by the application composition boundary.
///
/// Its responsibility is to construct and register filesystem
/// commands using those dependencies.
///
/// The module does not select concrete rendering backends.
/// That responsibility belongs to RudraCli.product() or
/// another application composition entry point.
///
/// Invariants:
/// - All commands share the configured SDK.
/// - The working directory belongs to the SDK's target.
/// - The renderer is supplied explicitly.
/// - Registration performs no filesystem inspection.
/// - Commands never authorize destructive operations.
///
/// The module does not:
/// - Access native filesystem adapters directly.
/// - Implement filesystem inspection algorithms.
/// - Format filesystem metadata.
/// - Write directly to terminal output.
/// - Manage persistent cleanup sessions.
/// - Modify filesystem content.
///
/// Example:
/// ```dart
/// final module = FilesystemCliModule(
///   sdk: sdk,
///   working_directory: TargetPath('/workspace'),
///   renderer: renderer,
/// );
///
/// cli.register_module(module);
/// ```
final class FilesystemCliModule implements RudraCliModule {
  /// Creates a filesystem module with explicit dependencies.
  ///
  /// [sdk] provides platform-independent filesystem services.
  ///
  /// [working_directory] supplies the default target-native
  /// directory for filesystem commands.
  ///
  /// [renderer] receives complete [FilesystemViewModel] presentations,
  /// including independent directory-listing and diagnostic components.
  ///
  /// Its concrete backend is selected by application composition.
  ///
  /// The caller must ensure that [working_directory] belongs
  /// to the filesystem target configured in [sdk].
  ///
  /// Construction performs no filesystem or terminal I/O.
  FilesystemCliModule({
    required RudraSdk sdk,
    required TargetPath working_directory,
    required Renderer<FilesystemViewModel> renderer,
  })  : _sdk = sdk,
        _working_directory = working_directory,
        _renderer = renderer;

  /// SDK shared by commands registered through this module.
  final RudraSdk _sdk;

  /// Default target-native directory for filesystem commands.
  final TargetPath _working_directory;

  /// Backend-independent renderer for composed filesystem presentations.
  final Renderer<FilesystemViewModel> _renderer;

  /// Stable identifier of Rudra's filesystem command module.
  @override
  String get module_id => 'rudra.product.filesystem';

  /// Creates commands contributed by the filesystem module.
  ///
  /// Command instances receive the SDK and renderer through
  /// explicit constructor injection.
  ///
  /// No filesystem inspection or mutation occurs here.
  ///
  /// The commands are owned by the registering CLI instance.
  @override
  Iterable<Command<int>> create_commands() {
    return [
      ListCommand(
        sdk: _sdk,
        working_directory: _working_directory,
        renderer: _renderer,
      ),
    ];
  }
}
