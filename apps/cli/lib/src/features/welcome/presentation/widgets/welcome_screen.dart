import '../../../../core/rendering/widgets/terminal_column.dart';
import '../../../../core/rendering/widgets/terminal_label.dart';
import '../../../../core/rendering/widgets/terminal_widget.dart';

import '../../../filesystem/presentation/widgets/directory_listing/directory_listing_widget.dart';

import '../welcome_view_model.dart';

import 'commands/welcome_commands.dart';
import 'footer/welcome_footer.dart';
import 'header/welcome_header.dart';
import 'target/welcome_target.dart';

/// Composes the complete non-interactive Welcome screen.
///
/// The screen delegates rendering to independently owned widgets.
///
/// It reuses [DirectoryListingWidget] without constructing a
/// filesystem-specific renderer or formatting entry metadata.
///
/// Inspection diagnostics are intentionally excluded from this
/// screen. The rendering adapter sends them separately to the
/// configured diagnostic output destination.
///
/// Layout is derived from child widget heights and their
/// declaration order using [TerminalColumn].
///
/// The screen never performs filesystem operations, manages
/// terminal modes, or changes application state.
///
/// Example:
/// ```dart
/// final screen = WelcomeScreen(welcome_view_model);
///
/// print(screen.height);
/// ```
final class WelcomeScreen implements TerminalWidget {
  /// Composes the header, target, optional listing, commands,
  /// and safety footer into a complete terminal widget tree.
  WelcomeScreen(WelcomeViewModel view_model)
      : _layout = TerminalColumn(
          children: [
            WelcomeHeader(view_model.header),
            WelcomeTarget(view_model.target),
            if (view_model.filesystem != null)
              DirectoryListingWidget(
                view_model.filesystem!.listing,
              ),
            if (view_model.filesystem != null) const TerminalLabel(''),
            WelcomeCommands(view_model.commands),
            WelcomeFooter(view_model.footer),
          ],
        );

  /// Root terminal widget composition.
  final TerminalColumn _layout;

  @override
  int get height => _layout.height;

  @override
  Iterable<TerminalLine> build(
    TerminalConstraints constraints,
  ) {
    return _layout.build(constraints);
  }
}
