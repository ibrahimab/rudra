import 'dart:io';

import 'package:rudra_sdk/rudra_sdk.dart';

/// Configures the connected SDK and its starting directory for one invocation.
///
/// ```dart
/// final composition = ProductSdkComposition.for_current_host();
/// try {
///   final sdk = await composition.connect();
///   await sdk.filesystem.list(directory: composition.working_directory);
/// } finally {
///   await composition.sdk.close();
/// }
/// ```
final class ProductSdkComposition {
  /// Creates an inactive production SDK composition.
  ///
  /// [sdk] supplies connected application services and transfers lifecycle ownership.
  /// [working_directory] supplies the initial target-native path.
  /// [connection_params] optionally selects an explicit endpoint.
  const ProductSdkComposition({
    required this.sdk,
    required this.working_directory,
    this.connection_params = const ConnectionParams(),
  });

  /// The SDK whose lifecycle belongs to the enclosing CLI invocation.
  final RudraSdk sdk;

  /// Initial path on the SDK's selected filesystem target.
  final TargetPath working_directory;

  /// Native default connectivity unless isolated composition overrides it.
  final ConnectionParams connection_params;

  /// Assembles the production frontend with native default connectivity.
  static ProductSdkComposition for_current_host() => ProductSdkComposition(
    sdk: RudraSdk(),
    working_directory: TargetPath(Directory.current.absolute.path),
  );

  /// Establishes the invocation's authenticated session and returns its SDK.
  ///
  /// Throws [CliHostUnavailableException] when establishment fails.
  Future<RudraSdk> connect() async {
    try {
      await sdk.connect(connection_params);
      return sdk;
    } catch (error, stack) {
      Error.throwWithStackTrace(CliHostUnavailableException(error), stack);
    }
  }
}

/// Reports that the frontend could not establish an authenticated host session.
final class CliHostUnavailableException implements Exception {
  /// Preserves the underlying connection [cause] for diagnostics.
  const CliHostUnavailableException(this.cause);

  /// The configuration, connectivity, authentication or disposal failure.
  final Object cause;
}
