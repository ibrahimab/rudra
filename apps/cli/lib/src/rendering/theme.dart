/// Defines semantic appearance roles shared by Rudra CLI views.
///
/// Roles describe what information represents, not how a
/// particular terminal rendering backend displays it.
///
/// A rendering implementation may translate these roles into
/// ANSI escape sequences, Nocterm widget styles, or plain text.
///
/// New roles should be introduced only when an actual
/// presentation requirement justifies them.
enum TerminalRole {
  /// Ordinary, unaccented text.
  text,

  /// Primary application or screen title.
  title,

  /// Section heading within a screen.
  heading,

  /// Current directory or another displayed target path.
  path,

  /// Filesystem directory entry.
  directory,

  /// Regular filesystem file.
  regular_file,

  /// Symbolic link, without implying its destination is known.
  symbolic_link,

  /// Filesystem entry of another or unknown kind.
  other_entry,

  /// Currently selected interactive entry.
  selected,

  /// Warning requiring user attention.
  warning,

  /// Error or failed operation.
  error,

  /// Secondary information or navigation hints.
  muted,
}

/// Basic foreground colors supported by Rudra's initial theme.
///
/// These are abstract color identifiers, not ANSI codes.
///
/// Rendering backends decide how to represent each color.
/// A backend without color support may ignore them.
///
/// Additional colors or richer color models can be introduced
/// when required by an implemented rendering backend.
enum TerminalColor {
  /// Blue accent.
  blue,

  /// Cyan accent.
  cyan,

  /// Green accent.
  green,

  /// Yellow warning accent.
  yellow,

  /// Red error accent.
  red,

  /// Neutral gray foreground.
  gray,
}

/// Immutable visual styling for terminal presentation.
///
/// A null [foreground] means the rendering backend's default
/// foreground color.
///
/// [bold] requests emphasized text.
///
/// [reverse] requests foreground/background inversion,
/// commonly used for highlighting the selected entry.
///
/// These properties are presentation hints. Rendering backends
/// may adapt them to their capabilities.
///
/// This class contains no ANSI escape sequences and performs
/// no terminal I/O.
///
/// Example:
/// ```dart
/// const style = TerminalStyle(
///   foreground: TerminalColor.cyan,
///   bold: true,
/// );
///
/// print(style.bold);
/// // true
/// ```
final class TerminalStyle {
  /// Creates an immutable terminal presentation style.
  const TerminalStyle({
    this.foreground,
    this.bold = false,
    this.reverse = false,
  });

  /// Requested foreground color, or null for the default.
  final TerminalColor? foreground;

  /// Whether text should receive strong emphasis.
  final bool bold;

  /// Whether foreground and background should be inverted.
  final bool reverse;

  /// Whether the style requests no special presentation.
  bool get is_plain => foreground == null && !bold && !reverse;
}

/// Defines semantic styling for Rudra CLI rendering.
///
/// A theme maps [TerminalRole] values to immutable
/// [TerminalStyle] definitions.
///
/// Themes are independent of:
/// - Filesystem and SDK services.
/// - Feature-specific presentation models.
/// - Terminal input and navigation.
/// - ANSI escape-sequence generation.
/// - Rendering frameworks such as Nocterm.
///
/// Styles supplied during construction are defensively copied.
/// Subsequent changes to the original map cannot modify the theme.
///
/// Roles without explicit styles use the plain default style.
///
/// Example:
/// ```dart
/// final theme = TerminalTheme.ansi;
///
/// final style = theme.style_for(
///   TerminalRole.directory,
/// );
///
/// print(style.foreground);
/// // TerminalColor.blue
/// ```
///
/// A rendering backend is responsible for applying the style.
final class TerminalTheme {
  /// Creates a theme with the supplied semantic styles.
  ///
  /// [name] is a nonempty identifier used for diagnostics
  /// and explicit application composition.
  ///
  /// [styles] associates semantic roles with visual styles.
  /// The map is copied to prevent external mutation.
  ///
  /// Missing roles default to an unstyled representation.
  ///
  /// Throws [ArgumentError] if [name] is blank.
  ///
  /// Construction performs no terminal or filesystem I/O.
  TerminalTheme({
    required String name,
    Map<TerminalRole, TerminalStyle> styles = const {},
  })  : name = _require_name(name),
        _styles = Map<TerminalRole, TerminalStyle>.unmodifiable(
          styles,
        );

  /// Identifier of this theme.
  final String name;

  /// Immutable mapping between semantic roles and styles.
  final Map<TerminalRole, TerminalStyle> _styles;

  /// Returns the style configured for [role].
  ///
  /// Unconfigured roles return a plain style.
  ///
  /// This method never modifies the theme.
  TerminalStyle style_for(TerminalRole role) {
    return _styles[role] ?? const TerminalStyle();
  }

  /// Plain theme without colors or terminal styling.
  ///
  /// Suitable for:
  /// - Redirected or piped output.
  /// - Non-interactive execution.
  /// - Deterministic text-based tests.
  /// - Terminals without ANSI styling support.
  ///
  /// Selection remains identifiable through textual markers
  /// supplied by the rendering implementation.
  static final TerminalTheme plain = TerminalTheme(
    name: 'plain',
  );

  /// Default colored theme for ANSI-capable terminals.
  ///
  /// This theme defines requested styles only.
  ///
  /// ANSI encoding belongs to the bare rendering backend,
  /// not to [TerminalTheme].
  ///
  /// Other rendering backends may interpret the same
  /// semantic styles using their own presentation APIs.
  static final TerminalTheme ansi = TerminalTheme(
    name: 'ansi',
    styles: {
      TerminalRole.title: const TerminalStyle(
        foreground: TerminalColor.cyan,
        bold: true,
      ),
      TerminalRole.heading: const TerminalStyle(
        foreground: TerminalColor.cyan,
        bold: true,
      ),
      TerminalRole.path: const TerminalStyle(
        foreground: TerminalColor.cyan,
      ),
      TerminalRole.directory: const TerminalStyle(
        foreground: TerminalColor.blue,
        bold: true,
      ),
      TerminalRole.regular_file: const TerminalStyle(),
      TerminalRole.symbolic_link: const TerminalStyle(
        foreground: TerminalColor.cyan,
      ),
      TerminalRole.other_entry: const TerminalStyle(
        foreground: TerminalColor.gray,
      ),
      TerminalRole.selected: const TerminalStyle(
        bold: true,
        reverse: true,
      ),
      TerminalRole.warning: const TerminalStyle(
        foreground: TerminalColor.yellow,
        bold: true,
      ),
      TerminalRole.error: const TerminalStyle(
        foreground: TerminalColor.red,
        bold: true,
      ),
      TerminalRole.muted: const TerminalStyle(
        foreground: TerminalColor.gray,
      ),
    },
  );

  /// Validates the theme identifier.
  ///
  /// The supplied spelling is preserved.
  static String _require_name(String name) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'Theme name must not be blank.',
      );
    }

    return name;
  }
}
