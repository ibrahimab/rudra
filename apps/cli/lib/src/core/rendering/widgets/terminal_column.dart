import 'terminal_widget.dart';

/// Composes terminal widgets vertically in declaration order.
///
/// Children are rendered from top to bottom.
///
/// The column height is the sum of its children's heights.
/// Consequently, layout height is derived from composition,
/// not maintained as a separate hardcoded value.
///
/// The child collection is defensively copied and immutable.
///
/// Example:
/// ```dart
/// final screen = TerminalColumn(
///   children: [
///     TerminalLabel('RUDRA', role: TerminalRole.title),
///     TerminalLabel('Ready'),
///   ],
/// );
///
/// print(screen.height);
/// // 2
/// ```
///
/// Child widgets must also fulfill their height contracts.
/// A violation produces [StateError] during building.
final class TerminalColumn implements TerminalWidget {
  /// Creates an immutable vertical widget composition.
  TerminalColumn({
    required List<TerminalWidget> children,
  }) : children = List<TerminalWidget>.unmodifiable(children);

  /// Child widgets in rendering order.
  final List<TerminalWidget> children;

  @override
  int get height {
    var total = 0;

    for (final child in children) {
      total += child.height;
    }

    return total;
  }

  @override
  Iterable<TerminalLine> build(
    TerminalConstraints constraints,
  ) sync* {
    for (final child in children) {
      final expected_height = child.height;

      if (expected_height < 0) {
        throw StateError('A widget cannot declare negative height.');
      }

      var actual_height = 0;

      for (final line in child.build(constraints)) {
        actual_height++;

        if (actual_height > expected_height) {
          throw StateError(
            'A child widget produced more rows than declared.',
          );
        }

        yield line;
      }

      if (actual_height != expected_height) {
        throw StateError(
          'A child widget produced fewer rows than declared.',
        );
      }
    }
  }
}
