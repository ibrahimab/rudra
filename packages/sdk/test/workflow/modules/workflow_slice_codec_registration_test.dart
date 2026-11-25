import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies feature-owned slice serialization registration,
/// atomic configuration and concrete type preservation.
void main() {
  group('slice codec registration', () {
    test('registers independently owned slice codecs', () {
      final registry = WorkflowModuleRegistry();

      registry.register(
        _TestModule('test.counter', (registration) {
          registration
            ..add_slice(_CounterSlice.key)
            ..add_slice_codec(_CounterSliceCodec());
        }),
      );

      registry.register(
        _TestModule('test.findings', (registration) {
          registration
            ..add_slice(_FindingsSlice.key)
            ..add_slice_codec(const _FindingsSliceCodec());
        }),
      );

      final runtime = WorkflowRuntime.from_registry(registry);

      expect(runtime.slice_codecs, hasLength(2));

      final counter = runtime.slice_codecs[_CounterSlice.key.id]!;
      final findings = runtime.slice_codecs[_FindingsSlice.key.id]!;

      expect(counter.key, _CounterSlice.key);
      expect(counter.key.slice_type, _CounterSlice);
      expect(counter.schema_version, 1);

      expect(findings.key, _FindingsSlice.key);
      expect(findings.key.slice_type, _FindingsSlice);
      expect(findings.schema_version, 1);
    });

    test('validates codec ownership independently of staging order', () {
      final registry = WorkflowModuleRegistry();

      registry.register(
        _TestModule('test.counter', (registration) {
          registration
            ..add_slice_codec(_CounterSliceCodec())
            ..add_slice(_CounterSlice.key);
        }),
      );

      expect(
        registry.slice_codecs[_CounterSlice.key.id]!.key,
        _CounterSlice.key,
      );
    });

    test('permits domain slices without serialization codecs', () {
      final registry = WorkflowModuleRegistry();

      registry.register(
        _TestModule('test.counter', (registration) {
          registration.add_slice(_CounterSlice.key);
        }),
      );

      final runtime = WorkflowRuntime.from_registry(registry);

      expect(runtime.slice_keys, hasLength(1));
      expect(runtime.slice_codecs, isEmpty);
    });

    test('rejects codecs without corresponding slice ownership', () {
      final registry = WorkflowModuleRegistry();

      expect(
        () => registry.register(
          _TestModule('test.counter', (registration) {
            registration.add_slice_codec(_CounterSliceCodec());
          }),
        ),
        throwsStateError,
      );

      expect(registry.slice_keys, isEmpty);
      expect(registry.slice_codecs, isEmpty);
    });

    test('rejects codecs contributed by another slice owner', () {
      final registry = WorkflowModuleRegistry();

      registry.register(
        _TestModule('test.counter', (registration) {
          registration.add_slice(_CounterSlice.key);
        }),
      );

      expect(
        () => registry.register(
          _TestModule('test.other', (registration) {
            registration.add_slice_codec(_CounterSliceCodec());
          }),
        ),
        throwsStateError,
      );

      expect(registry.slice_keys, hasLength(1));
      expect(registry.slice_codecs, isEmpty);
    });

    test('rejects matching identifiers with incompatible slice types', () {
      final registry = WorkflowModuleRegistry();

      expect(
        () => registry.register(
          _TestModule('test.incompatible', (registration) {
            registration
              ..add_slice(
                WorkflowSliceKey<_FindingsSlice>(_CounterSlice.key.id),
              )
              ..add_slice_codec(_CounterSliceCodec());
          }),
        ),
        throwsStateError,
      );

      expect(registry.slice_keys, isEmpty);
      expect(registry.slice_codecs, isEmpty);
    });

    test('rejects duplicate codecs for one slice', () {
      final registry = WorkflowModuleRegistry();

      expect(
        () => registry.register(
          _TestModule('test.counter', (registration) {
            registration
              ..add_slice(_CounterSlice.key)
              ..add_slice_codec(_CounterSliceCodec())
              ..add_slice_codec(_CounterSliceCodec());
          }),
        ),
        throwsStateError,
      );

      expect(registry.slice_keys, isEmpty);
      expect(registry.slice_codecs, isEmpty);
    });

    test('rejects multiple configured schema versions for one slice', () {
      final registry = WorkflowModuleRegistry();

      expect(
        () => registry.register(
          _TestModule('test.counter', (registration) {
            registration
              ..add_slice(_CounterSlice.key)
              ..add_slice_codec(_CounterSliceCodec())
              ..add_slice_codec(_CounterSliceCodec(schema_version: 2));
          }),
        ),
        throwsStateError,
      );

      expect(registry.slice_codecs, isEmpty);
    });

    test('rejects nonpositive slice schema versions', () {
      final registry = WorkflowModuleRegistry();

      for (final version in [0, -1]) {
        expect(
          () => registry.register(
            _TestModule('test.counter', (registration) {
              registration
                ..add_slice(_CounterSlice.key)
                ..add_slice_codec(_CounterSliceCodec(schema_version: version));
            }),
          ),
          throwsArgumentError,
        );

        expect(registry.slice_keys, isEmpty);
        expect(registry.slice_codecs, isEmpty);
      }
    });

    test('does not execute serialization during registration', () {
      final registry = WorkflowModuleRegistry();

      registry.register(
        _TestModule('test.counter', (registration) {
          registration
            ..add_slice(_CounterSlice.key)
            ..add_slice_codec(_CounterSliceCodec(fail_on_use: true));
        }),
      );

      final runtime = WorkflowRuntime.from_registry(registry);

      expect(runtime.slice_codecs, hasLength(1));
    });
  });

  group('atomic configuration ownership', () {
    test('failed registration preserves accepted module contributions', () {
      final registry = WorkflowModuleRegistry();

      registry.register(
        _TestModule('test.counter', (registration) {
          registration
            ..add_slice(_CounterSlice.key)
            ..add_slice_codec(_CounterSliceCodec());
        }),
      );

      final accepted = registry.slice_codecs[_CounterSlice.key.id];

      expect(
        () => registry.register(
          _TestModule('test.findings', (registration) {
            registration
              ..add_slice(_FindingsSlice.key)
              ..add_slice_codec(const _FindingsSliceCodec())
              ..add_slice_codec(_CounterSliceCodec());
          }),
        ),
        throwsStateError,
      );

      expect(registry.slice_keys, hasLength(1));
      expect(registry.slice_codecs, hasLength(1));

      expect(registry.slice_codecs[_CounterSlice.key.id], same(accepted));

      expect(registry.slice_keys.containsKey(_FindingsSlice.key.id), isFalse);

      // A rejected contribution must not reserve its module
      // identifier or any of its staged slice identities.
      registry.register(
        _TestModule('test.findings', (registration) {
          registration
            ..add_slice(_FindingsSlice.key)
            ..add_slice_codec(const _FindingsSliceCodec());
        }),
      );

      expect(registry.slice_keys, hasLength(2));
      expect(registry.slice_codecs, hasLength(2));
    });

    test('registry and runtime retain immutable configuration snapshots', () {
      final registry = WorkflowModuleRegistry();

      registry.register(
        _TestModule('test.counter', (registration) {
          registration
            ..add_slice(_CounterSlice.key)
            ..add_slice_codec(_CounterSliceCodec());
        }),
      );

      final registered = registry.slice_codecs;
      final runtime = WorkflowRuntime.from_registry(registry);

      registry.register(
        _TestModule('test.findings', (registration) {
          registration
            ..add_slice(_FindingsSlice.key)
            ..add_slice_codec(const _FindingsSliceCodec());
        }),
      );

      expect(registered, hasLength(1));
      expect(runtime.slice_codecs, hasLength(1));
      expect(registry.slice_codecs, hasLength(2));

      expect(() => registered.clear(), throwsUnsupportedError);

      expect(() => runtime.slice_codecs.clear(), throwsUnsupportedError);
    });
  });

  group('typed codec invocation', () {
    test('preserves concrete bindings through heterogeneous storage', () {
      final registry = WorkflowModuleRegistry();

      registry.register(
        _TestModule('test.counter', (registration) {
          registration
            ..add_slice(_CounterSlice.key)
            ..add_slice_codec(_CounterSliceCodec());
        }),
      );

      final runtime = WorkflowRuntime.from_registry(registry);

      final RegisteredWorkflowSliceCodec<WorkflowSlice> codec =
          runtime.slice_codecs[_CounterSlice.key.id]!;

      final original = WorkflowSliceBinding<_CounterSlice>(
        key: _CounterSlice.key,
        value: const _CounterSlice(42),
      );

      final payload = codec.encode_binding(original);

      expect(payload, 42);

      final restored = codec.decode_binding(payload);

      expect(restored, isA<WorkflowSliceBinding<_CounterSlice>>());
      expect(restored.key, _CounterSlice.key);
      expect(restored.value, isA<_CounterSlice>());

      expect((restored.value as _CounterSlice).count, 42);
    });

    test('rejects widened registration types', () {
      expect(
        () => RegisteredWorkflowSliceCodec<WorkflowSlice>(
          codec: _CounterSliceCodec(),
        ),
        throwsStateError,
      );
    });

    test('rejects bindings with another slice identity', () {
      final codec = RegisteredWorkflowSliceCodec<_CounterSlice>(
        codec: _CounterSliceCodec(),
      );

      final binding = WorkflowSliceBinding<_CounterSlice>(
        key: WorkflowSliceKey<_CounterSlice>('test.other-counter'),
        value: const _CounterSlice(42),
      );

      expect(() => codec.encode_binding(binding), throwsStateError);
    });

    test('rejects bindings with another concrete slice type', () {
      final codec = RegisteredWorkflowSliceCodec<_CounterSlice>(
        codec: _CounterSliceCodec(),
      );

      final binding = WorkflowSliceBinding<_FindingsSlice>(
        key: WorkflowSliceKey<_FindingsSlice>(_CounterSlice.key.id),
        value: const _FindingsSlice('finding'),
      );

      expect(() => codec.encode_binding(binding), throwsStateError);
    });

    test('rejects subtype values during encoding', () {
      final codec = RegisteredWorkflowSliceCodec<_CounterSlice>(
        codec: _CounterSliceCodec(),
      );

      final binding = WorkflowSliceBinding<_CounterSlice>(
        key: _CounterSlice.key,
        value: const _CounterSubtype(42),
      );

      expect(() => codec.encode_binding(binding), throwsStateError);
    });

    test('rejects codecs returning an unexpected concrete subtype', () {
      final codec = RegisteredWorkflowSliceCodec<_CounterSlice>(
        codec: _CounterSliceCodec(decode_subtype: true),
      );

      expect(() => codec.decode_binding(42), throwsStateError);
    });

    test('propagates feature payload decoding failures', () {
      final codec = RegisteredWorkflowSliceCodec<_CounterSlice>(
        codec: _CounterSliceCodec(),
      );

      expect(
        () => codec.decode_binding('invalid-counter'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

/// Synthetic module contributing independently owned domain capabilities.
final class _TestModule implements WorkflowModule {
  /// Creates a module with [module_id] and its [contribute] callback.
  const _TestModule(this.module_id, this.contribute);

  /// Stable identity of the synthetic module.
  @override
  final String module_id;

  /// Callback supplying the module's staged contributions.
  final void Function(WorkflowModuleRegistration) contribute;

  /// Contributes the configured capabilities to [registration].
  @override
  void register(WorkflowModuleRegistration registration) {
    contribute(registration);
  }
}

/// Immutable synthetic counter state.
///
/// Allows a subtype solely to exercise exact-type codec validation.
base class _CounterSlice extends WorkflowSlice {
  /// Creates a counter slice containing [count].
  const _CounterSlice(this.count);

  /// Stable typed identity of the counter slice.
  static final key = WorkflowSliceKey<_CounterSlice>('test.counter');

  /// Current synthetic counter value.
  final int count;
}

/// Synthetic subtype used to verify exact concrete type enforcement.
final class _CounterSubtype extends _CounterSlice {
  /// Creates a subtype containing [count].
  const _CounterSubtype(super.count);
}

/// Immutable state belonging to an independent synthetic feature.
final class _FindingsSlice extends WorkflowSlice {
  /// Creates a findings slice containing [finding].
  const _FindingsSlice(this.finding);

  /// Stable typed identity of the findings slice.
  static final key = WorkflowSliceKey<_FindingsSlice>('test.findings');

  /// Synthetic inspection finding.
  final String finding;
}

/// Synthetic counter serializer with configurable integrity test behavior.
final class _CounterSliceCodec implements WorkflowSliceCodec<_CounterSlice> {
  /// Creates a counter codec supporting [schema_version].
  ///
  /// [decode_subtype] deliberately violates the exact concrete
  /// type contract when enabled.
  ///
  /// [fail_on_use] throws if serialization is invoked.
  const _CounterSliceCodec({
    this.schema_version = 1,
    this.decode_subtype = false,
    this.fail_on_use = false,
  });

  /// Stable identity of the represented counter slice.
  @override
  WorkflowSliceKey<_CounterSlice> get key => _CounterSlice.key;

  /// Configured schema version for registration tests.
  @override
  final int schema_version;

  /// Whether decoding deliberately returns a concrete subtype.
  final bool decode_subtype;

  /// Whether serialization invocation deliberately fails.
  final bool fail_on_use;

  /// Returns the counter value represented by [slice].
  ///
  /// Throws [StateError] when serialization invocation is disabled.
  @override
  Object? encode(_CounterSlice slice) {
    if (fail_on_use) {
      throw StateError('Unexpected counter encoding.');
    }

    return slice.count;
  }

  /// Reconstructs a counter slice from [payload].
  ///
  /// Throws [FormatException] for non-integer payloads.
  /// Throws [StateError] when serialization invocation is disabled.
  @override
  _CounterSlice decode(Object? payload) {
    if (fail_on_use) {
      throw StateError('Unexpected counter decoding.');
    }

    if (payload is! int) {
      throw const FormatException('Invalid counter payload.');
    }

    return decode_subtype ? _CounterSubtype(payload) : _CounterSlice(payload);
  }
}

/// Serializer belonging to the independent findings feature.
final class _FindingsSliceCodec implements WorkflowSliceCodec<_FindingsSlice> {
  /// Creates the stateless findings codec.
  const _FindingsSliceCodec();

  /// Stable identity of the represented findings slice.
  @override
  WorkflowSliceKey<_FindingsSlice> get key => _FindingsSlice.key;

  /// Supported findings payload schema version.
  @override
  int get schema_version => 1;

  /// Returns the finding represented by [slice].
  @override
  Object? encode(_FindingsSlice slice) => slice.finding;

  /// Reconstructs findings state from [payload].
  ///
  /// Throws [FormatException] for non-string payloads.
  @override
  _FindingsSlice decode(Object? payload) {
    if (payload is! String) {
      throw const FormatException('Invalid findings payload.');
    }

    return _FindingsSlice(payload);
  }
}
