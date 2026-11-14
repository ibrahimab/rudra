import 'package:rudra_cli/src/core/rendering/bare/ansi_text.dart';
import 'package:rudra_cli/src/core/rendering/bare/bare_widget_renderer.dart';
import 'package:rudra_cli/src/core/rendering/theme.dart';
import 'package:rudra_cli/src/core/rendering/widgets/terminal_column.dart';
import 'package:rudra_cli/src/core/rendering/widgets/terminal_label.dart';
import 'package:rudra_cli/src/core/rendering/widgets/terminal_widget.dart';
import 'package:test/test.dart';

/// Tests the shared terminal widget composition infrastructure.
///
/// No CLI feature, filesystem adapter, SDK service, or actual
/// terminal is used by these tests.
void main() {
  group('Terminal widgets', () {
    test('composes nested widgets in declaration order', () {
      final screen = TerminalColumn(
        children: [
          const TerminalLabel('RUDRA'),
          TerminalColumn(
            children: [
              const TerminalLabel('Header'),
              const TerminalLabel('Content'),
            ],
          ),
          const TerminalLabel('Footer'),
        ],
      );

      expect(screen.height, 4);

      final lines = screen.build(TerminalConstraints(columns: 80)).toList();

      expect(
        lines.map((line) => line.text),
        orderedEquals(['RUDRA', 'Header', 'Content', 'Footer']),
      );
    });

    test('defensively copies widget children', () {
      final children = <TerminalWidget>[const TerminalLabel('Original')];

      final column = TerminalColumn(children: children);

      children.add(const TerminalLabel('Added later'));

      expect(column.height, 1);
      expect(column.children, hasLength(1));

      expect(
        () => column.children.add(const TerminalLabel('Invalid')),
        throwsUnsupportedError,
      );
    });

    test('empty column occupies zero rows', () {
      final column = TerminalColumn(children: []);

      expect(column.height, 0);

      expect(column.build(TerminalConstraints(columns: 80)), isEmpty);
    });

    test('retains semantic styling information', () {
      final label = TerminalLabel('RUDRA', role: TerminalRole.title);

      final line = label.build(TerminalConstraints(columns: 80)).single;

      expect(line.text, 'RUDRA');
      expect(line.role, TerminalRole.title);
    });

    test('rejects negative terminal width', () {
      expect(() => TerminalConstraints(columns: -1), throwsRangeError);
    });

    test('rejects children violating their row contracts', () {
      final column = TerminalColumn(children: [_IncorrectHeightWidget()]);

      expect(
        () => column.build(TerminalConstraints(columns: 80)).toList(),
        throwsStateError,
      );
    });

    test('supports explicitly unbounded constraints', () {
      final constraints = TerminalConstraints();

      expect(constraints.is_bounded, isFalse);
      expect(constraints.columns, isNull);

      expect(() => constraints.require_bounded_columns(), throwsStateError);
    });

    test('returns a required bounded width', () {
      final constraints = TerminalConstraints(columns: 80);

      expect(constraints.is_bounded, isTrue);
      expect(constraints.require_bounded_columns(), 80);
    });
  });

  group('BareWidgetRenderer', () {
    test('renders a composed screen', () {
      final output = StringBuffer();

      final renderer = BareWidgetRenderer(
        output: output,
        terminal_columns: () => 80,
      );

      renderer.render(
        TerminalColumn(
          children: [
            const TerminalLabel('RUDRA'),
            const TerminalLabel('Ready'),
          ],
        ),
      );

      expect(output.toString(), 'RUDRA\nReady\n');
    });

    test('sanitizes untrusted text', () {
      final output = StringBuffer();

      BareWidgetRenderer(
        output: output,
        terminal_columns: () => 80,
      ).render(const TerminalLabel('Unsafe\x1B[2J'));

      expect(output.toString(), 'Unsafe?[2J\n');
      expect(output.toString(), isNot(contains('\x1B')));
    });

    test('truncates to the current terminal width', () {
      var width = 5;
      final output = StringBuffer();

      final renderer = BareWidgetRenderer(
        output: output,
        terminal_columns: () => width,
      );

      renderer.render(const TerminalLabel('abcdefghij'));

      expect(output.toString(), 'abcd…\n');

      output.clear();
      width = 20;

      renderer.render(const TerminalLabel('abcdefghij'));

      expect(output.toString(), 'abcdefghij\n');
    });

    test('supports controlled ANSI screen redraw', () {
      final output = StringBuffer();

      final renderer = BareWidgetRenderer(
        output: output,
        terminal_columns: () => 80,
        theme: TerminalTheme.ansi,
        ansi_text: const AnsiText(enabled: true),
        redraw_screen: true,
      );

      renderer.render(const TerminalLabel('RUDRA', role: TerminalRole.title));

      expect(output.toString(), startsWith('\x1B[H\x1B[2J'));
      expect(output.toString(), contains('RUDRA'));
    });

    test('rejects redraw without ANSI support', () {
      expect(
        () => BareWidgetRenderer(
          output: StringBuffer(),
          terminal_columns: () => 80,
          redraw_screen: true,
        ),
        throwsArgumentError,
      );
    });

    test('does not write partially built widget trees', () {
      final output = StringBuffer();

      final renderer = BareWidgetRenderer(
        output: output,
        terminal_columns: () => 80,
      );

      expect(
        () => renderer.render(
          TerminalColumn(
            children: [const TerminalLabel('Valid'), _IncorrectHeightWidget()],
          ),
        ),
        throwsStateError,
      );

      expect(output.toString(), isEmpty);
    });

    test('preserves long text in unbounded output', () {
      final output = StringBuffer();
      final long_text = List<String>.filled(240, 'x').join();

      final renderer = BareWidgetRenderer(output: output);

      renderer.render(TerminalLabel(long_text));

      expect(output.toString(), '$long_text\n');
    });

    test('sanitizes unbounded output without truncating it', () {
      final output = StringBuffer();
      final long_text = List<String>.filled(160, 'x').join();

      BareWidgetRenderer(output: output)
          .render(TerminalLabel('$long_text\x1B[2J'));

      expect(output.toString(), '$long_text?[2J\n');

      expect(output.toString(), isNot(contains('\x1B')));
    });
  });
}

/// A deliberately malformed widget used to test height validation.
final class _IncorrectHeightWidget implements TerminalWidget {
  @override
  int get height => 2;

  @override
  Iterable<TerminalLine> build(TerminalConstraints constraints) sync* {
    yield const TerminalLine('Only one row');
  }
}
