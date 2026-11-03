import 'dart:io';
import 'package:rudra_cli/rudra_cli.dart';

/// Identifies a package belonging to the Rudra Dart workspace.
///
/// The package name is used for CLI filtering, while the path identifies
/// its location relative to the workspace root.
///
/// This object contains discovery metadata only. It does not indicate
/// that a package supports a particular target or has runnable tests.
final class WorkspacePackage {
  /// Creates an immutable workspace package description.
  const WorkspacePackage({
    required this.name,
    required this.path,
  });

  /// Package name declared by its pubspec.
  final String name;

  /// Directory path relative to the workspace root.
  final String path;
}

/// Parses the output of `dart pub workspace list`.
///
/// Expected output starts with `Package` and `Path` column headers,
/// followed by one row per workspace member.
///
/// The function fails explicitly when the output cannot be parsed,
/// rather than silently omitting packages.
///
/// Throws [FormatException] for invalid headers, malformed entries,
/// or listings containing no packages.
///
/// Example:
/// ```dart
/// final packages = parse_workspace_packages(
///   'Package     Path\n'
///   'rudra_cli   apps/cli/\n',
/// );
///
/// assert(packages.first.name == 'rudra_cli');
/// assert(packages.first.path == 'apps/cli/');
/// ```
List<WorkspacePackage> parse_workspace_packages(String output) {
  final lines = output.split(RegExp(r'\r?\n'));

  if (!RegExp(r'^Package\s+Path$').hasMatch(lines.first.trim())) {
    throw const FormatException(
      'Unexpected workspace listing header.',
    );
  }

  final packages = <WorkspacePackage>[];

  for (final line in lines.skip(1)) {
    if (line.trim().isEmpty) {
      continue;
    }

    // Package names contain no whitespace, and the CLI separates
    // table columns with at least two whitespace characters.
    final match = RegExp(
      r'^\s*(\S+)\s{2,}(.+?)\s*$',
    ).firstMatch(line);

    if (match == null) {
      throw FormatException(
        'Invalid workspace package entry: $line',
      );
    }

    packages.add(
      WorkspacePackage(
        name: match.group(1)!,
        path: match.group(2)!.trim(),
      ),
    );
  }

  if (packages.isEmpty) {
    throw const FormatException(
      'No workspace packages discovered.',
    );
  }

  return List<WorkspacePackage>.unmodifiable(packages);
}

/// Extracts workspace paths from Dart's package listing.
///
/// Preserved for compatibility with the existing parser tests.
/// New functionality should use [parse_workspace_packages], which
/// retains both the package name and directory path.
List<String> parse_workspace_paths(String output) {
  return parse_workspace_packages(output)
      .map((package) => package.path)
      .toList(growable: false);
}

/// Constructs the arguments passed to Dart's package test runner.
///
/// Each supplied filter is forwarded without rewriting its meaning.
/// This allows Dart's test framework to handle regular expressions
/// and tag selector expressions using its documented semantics.
///
/// Null filters are omitted entirely.
///
/// Example:
/// ```dart
/// final arguments = build_test_arguments(
///   test_name: 'TargetDescriptor',
///   exclude_tags: 'slow',
/// );
///
/// assert(arguments.first == 'test');
/// ```
List<String> build_test_arguments({
  String? test_name,
  String? tags,
  String? exclude_tags,
}) {
  final arguments = <String>['test'];

  if (test_name != null) {
    arguments.addAll(['--name', test_name]);
  }

  if (tags != null) {
    arguments.addAll(['--tags', tags]);
  }

  if (exclude_tags != null) {
    arguments.addAll(['--exclude-tags', exclude_tags]);
  }

  return arguments;
}

/// Provides development operations for the Rudra monorepo.
///
/// Every task executes relative to [repo_root], except package tests,
/// which execute within their respective workspace package.
///
/// Commands run sequentially and stop on failure. A failed command
/// never reports overall success.
///
/// This service is exclusively for development tooling.
/// It must not be imported by production application code.
final class DevTasks {
  /// Creates a development task service for the repository.
  DevTasks(this.repo_root);

  /// Absolute or relative directory containing the workspace pubspec.
  final Directory repo_root;

  /// Runs the repository quality gate.
  ///
  /// By default, the quality gate covers the entire workspace.
  ///
  /// If [package_name] is provided, formatting, static analysis,
  /// and tests are restricted to that workspace member.
  ///
  /// Dependency resolution remains workspace-wide because all
  /// packages share the same Pub Workspace dependency resolution.
  ///
  /// The command stops at the first failed verification stage.
  ///
  /// Returns the failing command's exit status, or
  /// [RudraExitCode.success] when all stages pass.
  Future<int> check({String? package_name}) async {
    final dependency_status = await _run_dart(['pub', 'get']);

    if (dependency_status != RudraExitCode.success.value) {
      return dependency_status;
    }

    var target_path = '.';

    if (package_name != null) {
      final discovery = await _discover_workspace_packages();

      if (discovery.packages == null) {
        return discovery.exit_code;
      }

      final matches = discovery.packages!
          .where((package) => package.name == package_name)
          .toList();

      if (matches.isEmpty) {
        stderr.writeln('Unknown workspace package: $package_name');
        return RudraExitCode.invalid_usage.value;
      }

      target_path = matches.single.path;
    }

    final stages = <List<String>>[
      [
        'format',
        '--output=none',
        '--set-exit-if-changed',
        target_path,
      ],
      ['analyze', target_path],
    ];

    for (final arguments in stages) {
      final status = await _run_dart(arguments);

      if (status != RudraExitCode.success.value) {
        return status;
      }
    }

    return test(package_name: package_name);
  }

  /// Applies Dart formatting to all repository source files.
  ///
  /// Unlike the formatting stage in [check], this command modifies
  /// source files. It runs only when explicitly invoked.
  Future<int> format() => _run_dart(['format', '.']);

  /// Runs static analysis across the workspace.
  ///
  /// Returns the analyzer's exit code without modifying source files.
  Future<int> analyze() => _run_dart(['analyze']);

  /// Executes the test suites of selected workspace packages.
  ///
  /// The workspace is queried dynamically to discover all members.
  /// Packages therefore require no manual test registration.
  ///
  /// [package_name] restricts execution to one workspace member.
  /// [test_name] filters matching test names using Dart's test runner.
  /// [tags] and [exclude_tags] filter using Dart tag selectors.
  ///
  /// Packages without test files are reported as skipped.
  ///
  /// Test suites execute sequentially, and execution stops on the
  /// first failing suite.
  ///
  /// An unknown package name or a selection with no runnable suites
  /// produces a nonzero status.
  ///
  /// Example:
  /// ```dart
  /// final status = await tasks.test(
  ///   package_name: 'rudra_target_contracts',
  ///   test_name: 'TargetDescriptor',
  /// );
  /// ```
  Future<int> test({
    String? package_name,
    String? test_name,
    String? tags,
    String? exclude_tags,
  }) async {
    final discovery = await _discover_workspace_packages();

    if (discovery.packages == null) {
      return discovery.exit_code;
    }

    final packages = discovery.packages!;

    final selected_packages = package_name == null
        ? packages
        : packages.where((package) => package.name == package_name).toList();

    if (selected_packages.isEmpty) {
      stderr.writeln('Unknown workspace package: $package_name');
      return RudraExitCode.invalid_usage.value;
    }

    final test_arguments = build_test_arguments(
      test_name: test_name,
      tags: tags,
      exclude_tags: exclude_tags,
    );

    var executed = 0;
    var skipped = 0;

    for (final package in selected_packages) {
      final package_directory = Directory(
        '${repo_root.path}/${package.path}',
      );

      final test_directory = Directory(
        '${package_directory.path}/test',
      );

      if (!test_directory.existsSync()) {
        stdout.writeln(
          'SKIP ${package.name} (no test directory)',
        );
        skipped++;
        continue;
      }

      // Only actual Dart test files make a suite runnable.
      // Symbolic links are not followed during discovery.
      final has_tests = test_directory
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .any((file) => file.path.endsWith('_test.dart'));

      if (!has_tests) {
        stdout.writeln(
          'SKIP ${package.name} (no test files)',
        );
        skipped++;
        continue;
      }

      stdout.writeln('TEST ${package.name}');

      final status = await _run_dart(
        test_arguments,
        working_directory: package_directory,
      );

      if (status != RudraExitCode.success.value) {
        return status;
      }

      executed++;
    }

    stdout.writeln(
      'Test summary: $executed suites passed, $skipped skipped.',
    );

    if (executed == 0) {
      stderr.writeln('No runnable test suites were discovered.');
      return RudraExitCode.software_error.value;
    }

    return RudraExitCode.success.value;
  }

  /// Compiles and verifies the production Rudra executable.
  ///
  /// The compilation root is the production entrypoint rather than
  /// the development entrypoint.
  ///
  /// After compilation, the binary's help output is inspected to
  /// verify that development commands are not publicly registered.
  ///
  /// Returns a nonzero status on compilation or verification failure.
  Future<int> build() async {
    final output_directory = Directory('${repo_root.path}/build');

    await output_directory.create(recursive: true);

    final binary_name = Platform.isWindows ? 'rudra.exe' : 'rudra';
    final binary_path = '${output_directory.path}/$binary_name';

    final status = await _run_dart([
      'compile',
      'exe',
      'apps/cli/bin/rudra.dart',
      '-o',
      binary_path,
    ]);

    if (status != 0) {
      return status;
    }

    final ProcessResult result;

    try {
      result = await Process.run(
        binary_path,
        ['--help'],
        workingDirectory: repo_root.path,
      );
    } on ProcessException catch (error) {
      stderr.writeln(error);
      return 1;
    }

    if (result.exitCode != 0) {
      stderr.write(result.stderr);
      return result.exitCode;
    }

    final help = result.stdout as String;

    // A valid production binary must advertise its product command.
    final product_command = RegExp(
      r'^\s+about\s',
      multiLine: true,
    );

    if (!product_command.hasMatch(help)) {
      stderr.writeln('Production command verification failed.');
      return 1;
    }

    const developer_commands = <String>[
      'check',
      'test',
      'analyze',
      'format',
      'build',
    ];

    for (final command in developer_commands) {
      final pattern = RegExp(
        '^\\s+${RegExp.escape(command)}\\s',
        multiLine: true,
      );

      if (pattern.hasMatch(help)) {
        stderr.writeln(
          'Developer command exposed in production: $command',
        );

        return 1;
      }
    }

    stdout.writeln('Production build verified: $binary_path');
    return 0;
  }

  /// Discovers the package names and paths in the current workspace.
  ///
  /// Uses Dart's workspace listing rather than maintaining a separate
  /// package registry in Rudra.
  ///
  /// The returned record contains:
  /// - `exit_code`: the outcome of the discovery operation.
  /// - `packages`: the discovered packages, or null on failure.
  ///
  /// A failed Dart subprocess retains its original exit status.
  /// Unexpected output formats produce a Rudra software error.
  ///
  /// This method performs no filesystem cleanup operations.
  Future<
      ({
        int exit_code,
        List<WorkspacePackage>? packages,
      })> _discover_workspace_packages() async {
    final ProcessResult result;

    try {
      result = await Process.run(
        'dart',
        ['pub', 'workspace', 'list'],
        workingDirectory: repo_root.path,
      );
    } on ProcessException catch (error) {
      stderr.writeln(error);

      return (
        exit_code: RudraExitCode.software_error.value,
        packages: null,
      );
    }

    if (result.exitCode != RudraExitCode.success.value) {
      stderr.write(result.stderr);

      return (
        exit_code: result.exitCode,
        packages: null,
      );
    }

    try {
      final packages = parse_workspace_packages(
        result.stdout as String,
      );

      return (
        exit_code: RudraExitCode.success.value,
        packages: packages,
      );
    } on FormatException catch (error) {
      stderr.writeln(error);

      return (
        exit_code: RudraExitCode.software_error.value,
        packages: null,
      );
    }
  }

  /// Starts a Dart subprocess and forwards its terminal output.
  ///
  /// [arguments] contains the Dart CLI arguments without the
  /// executable name.
  ///
  /// [working_directory] overrides the repository root when provided.
  ///
  /// The child process inherits the terminal's standard streams.
  /// Returns its exit code, or `1` if process startup fails.
  Future<int> _run_dart(
    List<String> arguments, {
    Directory? working_directory,
  }) async {
    stdout.writeln('> dart ${arguments.join(' ')}');

    try {
      final process = await Process.start(
        'dart',
        arguments,
        workingDirectory: (working_directory ?? repo_root).path,
        mode: ProcessStartMode.inheritStdio,
      );

      return await process.exitCode;
    } on ProcessException catch (error) {
      stderr.writeln(error);
      return 1;
    }
  }
}
