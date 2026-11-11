import 'dart:async';

/// Defines the terminal environment required by the CLI Explorer.
///
/// An Explorer terminal host owns the terminal interaction boundary.
///
/// It provides:
/// - Interactive terminal capability detection.
/// - Current terminal dimensions.
/// - A raw terminal input byte stream.
/// - An output destination for interactive rendering.
/// - A guarded terminal interaction lifecycle.
///
/// Implementations may use dart:io or a different terminal backend.
///
/// The contract is specific to the Explorer feature.
/// It does not establish a general-purpose CLI terminal framework.
///
/// The host does not:
/// - Interpret Explorer navigation keys.
/// - Call Rudra SDK application services.
/// - Inspect or modify filesystem entries.
/// - Manage navigation or presentation state.
/// - Create persistent inspection sessions.
/// - Authorize or execute cleanup operations.
///
/// Example:
/// ```dart
/// final result = await host.run_interactive(() async {
///   final input = TerminalInput(
///     source: host.input_bytes,
///   );
///
///   await for (final key in input.read_keys()) {
///     if (key == ExplorerKey.quit) {
///       break;
///     }
///   }
///
///   return RudraExitCode.success.value;
/// });
/// ```
///
/// TerminalInput and RudraExitCode are supplied by the
/// calling Explorer application and are not host dependencies.
abstract interface class ExplorerTerminalHost {
  /// Whether this host can support an interactive Explorer.
  ///
  /// A true result means that both input and output are
  /// interactive and required terminal capabilities are available.
  ///
  /// Redirected input, redirected output, or an unsupported
  /// terminal configuration must not report true.
  ///
  /// Capability detection performs no filesystem mutation
  /// or terminal-mode changes.
  bool get is_interactive;

  /// Current number of terminal display columns.
  ///
  /// Implementations must return a nonnegative value.
  ///
  /// Zero represents an unknown or unavailable width.
  ///
  /// The value may change during an active interaction.
  int get terminal_columns;

  /// Current number of terminal display rows.
  ///
  /// Implementations must return a nonnegative value.
  ///
  /// Zero represents an unknown or unavailable height.
  ///
  /// The interactive runner is responsible for subtracting
  /// fixed screen content when calculating the entry viewport.
  ///
  /// The value may change during an active interaction.
  int get terminal_rows;

  /// Raw terminal input bytes for the active interaction.
  ///
  /// Input is supplied as ordered byte chunks.
  ///
  /// Escape sequences may cross chunk boundaries.
  /// Interpretation belongs to [TerminalInput], not this host.
  ///
  /// The stream may complete or produce errors.
  /// Errors must not be silently converted into normal input.
  ///
  /// Implementations must document their subscription and
  /// cancellation behavior.
  ///
  /// Callers must consume the stream only during an active
  /// [run_interactive] invocation.
  Stream<List<int>> get input_bytes;

  /// Output destination used by interactive renderers.
  ///
  /// The host supplies the destination but does not interpret
  /// feature-specific view models or filesystem observations.
  ///
  /// Rendering implementations own their ANSI formatting.
  ///
  /// Output sink failures propagate to the interaction.
  StringSink get output;

  /// Executes one interaction while owning terminal lifecycle.
  ///
  /// Before invoking [interaction], implementations must:
  /// - Verify that interactive terminal operation is supported.
  /// - Reject concurrent or nested interactions.
  /// - Preserve the original terminal configuration.
  /// - Activate the required interactive input and display modes.
  ///
  /// Implementations must restore changed terminal state
  /// after normal completion or a thrown exception.
  ///
  /// Restoration includes any altered:
  /// - Input line mode.
  /// - Input echo settings.
  /// - Alternate-screen state.
  /// - Cursor visibility.
  ///
  /// Restoration must also be attempted for catchable
  /// process-interruption signals supported by the host.
  ///
  /// The host must not claim protection against SIGKILL,
  /// process crashes, power loss, or other situations in which
  /// application cleanup code cannot execute.
  ///
  /// If terminal setup fails partway through, restoration
  /// must still be attempted for every change already made.
  ///
  /// The returned future completes with [interaction]'s result
  /// when the interaction and terminal restoration succeed.
  ///
  /// Unexpected interaction errors must not be converted into
  /// successful completion.
  ///
  /// Unsupported terminal configurations and invalid lifecycle
  /// use must produce explicit failures without enabling
  /// interactive terminal modes.
  ///
  /// Implementations must document how simultaneous interaction
  /// and restoration failures are reported.
  ///
  /// No filesystem inspection or cleanup is performed by
  /// this lifecycle operation itself.
  Future<T> run_interactive<T>(
    Future<T> Function() interaction,
  );
}
