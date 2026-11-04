import 'dart:io';

import 'package:rudra_sdk/rudra_sdk.dart';

import '../../composition/product_sdk_composition.dart';
import '../../rudra_exit_code.dart';
import 'welcome_model.dart';
import 'welcome_view.dart';

/// Coordinates the CLI's initial welcome workflow.
///
/// Requests filesystem observations through the public Rudra SDK
/// and delegates terminal presentation to [WelcomeView].
///
/// The controller never accesses TargetInspector directly and
/// never executes filesystem mutations or session operations.
final class WelcomeController {
  /// Creates a controller using the configured SDK composition.
  ///
  /// A null [composition] represents an unsupported target.
  ///
  /// [output] receives presentation output.
  /// [error_output] receives inspection diagnostics.
  ///
  /// Construction does not inspect the filesystem.
  WelcomeController({
    required ProductSdkComposition? composition,
    required StringSink output,
    StringSink? error_output,
    WelcomeView view = const WelcomeView(),
  })  : _composition = composition,
        _output = output,
        _error_output = error_output ?? stderr,
        _view = view;

  /// SDK and target configuration supplied by the CLI.
  final ProductSdkComposition? _composition;

  /// Terminal presentation destination.
  final StringSink _output;

  /// Diagnostic destination.
  final StringSink _error_output;

  /// Stateless welcome presentation.
  final WelcomeView _view;

  /// Inspects the starting directory and displays the welcome view.
  ///
  /// Each supported invocation performs one SDK listing request
  /// against the configured starting directory.
  ///
  /// Returns success for a complete listing or an unavailable
  /// target, and inspection_incomplete for partial observations.
  ///
  /// Unexpected SDK errors propagate without being disguised
  /// as successful or empty results.
  ///
  /// This workflow is strictly read-only.
  Future<int> show() async {
    final composition = _composition;

    // Only the SDK performs filesystem observations.
    final DirectoryListing? listing = composition == null
        ? null
        : await composition.sdk.filesystem.list(
            directory: composition.working_directory,
          );

    final model = WelcomeModel(
      product_name: application_name,
      target_id: composition?.sdk.target_id,
      starting_directory: composition?.working_directory,
      listing: listing,
    );

    _view.render(
      model,
      output: _output,
      error_output: _error_output,
    );

    if (listing != null && !listing.is_complete) {
      return RudraExitCode.inspection_incomplete.value;
    }

    return RudraExitCode.success.value;
  }
}
