import 'package:rudra_sdk/rudra_sdk.dart';

/// Constructs an independent workflow runtime for serialization tests.
///
/// [features] supplies the additional synthetic workflow modules.
/// The standard lifecycle module is always registered.
///
/// Returns the immutable configuration produced by the registry.
WorkflowRuntime create_serialization_runtime({
  required Iterable<WorkflowModule> features,
}) {
  final registry = WorkflowModuleRegistry();

  registry.register(const LifecycleWorkflowModule());

  for (final feature in features) {
    registry.register(feature);
  }

  return WorkflowRuntime.from_registry(registry);
}

/// Immutable state owned by the synthetic counter feature.
final class CounterSlice extends WorkflowSlice {
  /// Creates a counter slice containing [count].
  const CounterSlice(this.count);

  /// Stable typed identity of the counter feature's slice.
  static final key = WorkflowSliceKey<CounterSlice>('test.counter');

  /// Current synthetic counter value.
  final int count;
}

/// Serialization capability owned by the synthetic counter feature.
final class CounterSliceCodec implements WorkflowSliceCodec<CounterSlice> {
  /// Creates the stateless counter codec.
  const CounterSliceCodec();

  /// Stable identity of the represented slice.
  @override
  WorkflowSliceKey<CounterSlice> get key => CounterSlice.key;

  /// Supported counter payload schema version.
  @override
  int get schema_version => 1;

  /// Returns the structured representation of [slice].
  @override
  Object? encode(CounterSlice slice) {
    return {'count': slice.count};
  }

  /// Reconstructs a counter slice from [payload].
  ///
  /// Throws [FormatException] for malformed counter representations.
  @override
  CounterSlice decode(Object? payload) {
    if (payload is! Map<String, Object?> ||
        payload.length != 1 ||
        payload['count'] is! int) {
      throw const FormatException('Invalid counter slice payload.');
    }

    return CounterSlice(payload['count'] as int);
  }
}

/// Independent workflow module owning counter state and serialization.
final class CounterFeatureModule implements WorkflowModule {
  /// Creates the synthetic counter feature.
  const CounterFeatureModule();

  /// Stable counter feature identity.
  @override
  String get module_id => 'test.counter.feature';

  /// Stable identifier of a synthetic nonterminal lifecycle.
  static const lifecycle_id = 'test.counter.processing';

  /// Contributes the counter feature's contracts to [registration].
  @override
  void register(WorkflowModuleRegistration registration) {
    registration
      ..add_lifecycle(WorkflowLifecycle(id: lifecycle_id, is_terminal: false))
      ..add_slice(CounterSlice.key)
      ..add_slice_codec(const CounterSliceCodec());
  }
}

/// Immutable state owned by the synthetic findings feature.
///
/// A null finding is a valid initialized slice value.
final class FindingsSlice extends WorkflowSlice {
  /// Creates a findings slice containing [finding].
  const FindingsSlice(this.finding);

  /// Stable typed identity of the findings feature's slice.
  static final key = WorkflowSliceKey<FindingsSlice>('test.findings');

  /// Optional synthetic finding.
  final String? finding;
}

/// Serialization capability owned by the synthetic findings feature.
final class FindingsSliceCodec implements WorkflowSliceCodec<FindingsSlice> {
  /// Creates the stateless findings codec.
  const FindingsSliceCodec();

  /// Stable identity of the represented slice.
  @override
  WorkflowSliceKey<FindingsSlice> get key => FindingsSlice.key;

  /// Supported findings payload schema version.
  @override
  int get schema_version => 1;

  /// Returns the optional finding represented by [slice].
  @override
  Object? encode(FindingsSlice slice) => slice.finding;

  /// Reconstructs a findings slice from [payload].
  ///
  /// Throws [FormatException] for values other than a string
  /// or explicit null.
  @override
  FindingsSlice decode(Object? payload) {
    if (payload != null && payload is! String) {
      throw const FormatException('Invalid findings slice payload.');
    }

    return FindingsSlice(payload as String?);
  }
}

/// Independent workflow module owning findings state and serialization.
final class FindingsFeatureModule implements WorkflowModule {
  /// Creates the synthetic findings feature.
  const FindingsFeatureModule();

  /// Stable findings feature identity.
  @override
  String get module_id => 'test.findings.feature';

  /// Contributes the findings feature's contracts to [registration].
  @override
  void register(WorkflowModuleRegistration registration) {
    registration
      ..add_slice(FindingsSlice.key)
      ..add_slice_codec(const FindingsSliceCodec());
  }
}

/// Synthetic domain feature with no serialization capability.
///
/// Verifies that domain execution can be configured independently
/// of state serialization.
final class DomainOnlyFeatureModule implements WorkflowModule {
  /// Creates the synthetic domain-only feature.
  const DomainOnlyFeatureModule();

  /// Stable domain-only feature identity.
  @override
  String get module_id => 'test.domain-only.feature';

  /// Contributes domain ownership without a codec to [registration].
  @override
  void register(WorkflowModuleRegistration registration) {
    registration.add_slice(CounterSlice.key);
  }
}
