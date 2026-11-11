import 'dart:convert';

import 'package:rudra_cli/src/features/explorer/terminal_input.dart';
import 'package:test/test.dart';

/// Verifies terminal keyboard decoding for the CLI explorer.
///
/// Tests use deterministic byte streams instead of real stdin.
///
/// No terminal settings are changed, and no filesystem
/// operations are performed.
void main() {
  group('TerminalInput', () {
    test('decodes supported navigation keys', () async {
      final keys = await _decode([
        ascii.encode('\x1B[A\x1B[B\x1B[D\r\b\x7FqQ'),
      ]);

      expect(
        keys,
        orderedEquals([
          ExplorerKey.up,
          ExplorerKey.down,
          ExplorerKey.back,
          ExplorerKey.open,
          ExplorerKey.back,
          ExplorerKey.back,
          ExplorerKey.quit,
          ExplorerKey.quit,
        ]),
      );
    });

    test('supports LF as an Enter key', () async {
      final keys = await _decode([
        ascii.encode('\n'),
      ]);

      expect(keys, [ExplorerKey.open]);
    });

    test('treats CRLF as one Enter event', () async {
      final keys = await _decode([
        ascii.encode('\r'),
        ascii.encode('\n'),
      ]);

      expect(keys, [ExplorerKey.open]);
    });

    test('decodes ANSI sequences across chunks', () async {
      final keys = await _decode([
        ascii.encode('\x1B'),
        ascii.encode('['),
        <int>[],
        ascii.encode('A\x1B'),
        ascii.encode('['),
        ascii.encode('B\x1B[D'),
      ]);

      expect(
        keys,
        orderedEquals([
          ExplorerKey.up,
          ExplorerKey.down,
          ExplorerKey.back,
        ]),
      );
    });

    test('supports SS3 cursor-key sequences', () async {
      final keys = await _decode([
        ascii.encode('\x1BOA'),
        ascii.encode('\x1BOB'),
        ascii.encode('\x1BOD'),
      ]);

      expect(
        keys,
        orderedEquals([
          ExplorerKey.up,
          ExplorerKey.down,
          ExplorerKey.back,
        ]),
      );
    });

    test('accepts modified CSI arrow sequences', () async {
      final keys = await _decode([
        ascii.encode('\x1B[1;5A'),
        ascii.encode('\x1B[1;3B'),
        ascii.encode('\x1B[1;2D'),
      ]);

      // Modifiers are intentionally ignored in Block 4C.2.
      expect(
        keys,
        orderedEquals([
          ExplorerKey.up,
          ExplorerKey.down,
          ExplorerKey.back,
        ]),
      );
    });

    test('ignores unsupported keys and sequences', () async {
      final keys = await _decode([
        ascii.encode('z0 '),
        ascii.encode('\x1B[C'),
        ascii.encode('\x1B[H'),
        ascii.encode('\x1BOF'),
        ascii.encode('\x1B[2~'),
        ascii.encode('q'),
      ]);

      expect(keys, [ExplorerKey.quit]);
    });

    test('ignores incomplete escape sequences at EOF', () async {
      final prefix = await _decode([
        ascii.encode('\x1B'),
      ]);

      final incomplete_csi = await _decode([
        ascii.encode('\x1B['),
        ascii.encode('1;5'),
      ]);

      expect(prefix, isEmpty);
      expect(incomplete_csi, isEmpty);
    });

    test('supports an empty input stream', () async {
      final keys = await _decode([]);

      expect(keys, isEmpty);
    });

    test('propagates source stream errors', () async {
      final source = Stream<List<int>>.error(
        StateError('Injected terminal read failure.'),
      );

      final input = TerminalInput(source: source);

      await expectLater(
        input.read_keys(),
        emitsError(isA<StateError>()),
      );
    });

    test('treats raw Ctrl+C as a controlled quit request', () async {
      final keys = await _decode([
        <int>[0x03],
      ]);

      expect(
        keys,
        orderedEquals([ExplorerKey.quit]),
      );
    });
  });
}

/// Decodes supplied input chunks into navigation events.
///
/// Each invocation creates a new source stream and decoder.
///
/// Chunk boundaries are preserved to verify that partial
/// ANSI escape sequences are handled correctly.
///
/// Example:
/// ```dart
/// final keys = await _decode([
///   ascii.encode('\x1B'),
///   ascii.encode('[A'),
/// ]);
///
/// // keys contains ExplorerKey.up.
/// ```
Future<List<ExplorerKey>> _decode(
  List<List<int>> chunks,
) {
  final input = TerminalInput(
    source: Stream<List<int>>.fromIterable(chunks),
  );

  return input.read_keys().toList();
}
