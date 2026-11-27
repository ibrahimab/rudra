import 'dart:async';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

void main() {
  late List<String> mutations;

  setUp(() {
    mutations = [];
  });

  group('HostInstaller', () {
    test('construction performs no resource operations', () {
      final step = InstallStep('storage', mutations);

      HostInstaller(steps: [step]);

      expect(step.inspection_count, 0);
      expect(mutations, isEmpty);
    });

    test('planning inspects without modifying resources', () async {
      final step = InstallStep('storage', mutations);
      final installer = HostInstaller(steps: [step]);

      final plan = await installer.plan();

      expect(plan.operation, HostInstallOperation.install);
      expect(plan.can_execute, isTrue);
      expect(plan.is_satisfied, isFalse);
      expect(plan.entries.single.step_id, 'storage');

      expect(
        plan.entries.single.inspection.disposition,
        HostInstallDisposition.change_required,
      );

      expect(step.inspection_count, 1);
      expect(step.installed, isFalse);
      expect(mutations, isEmpty);
    });

    test('installs in dependency order and verifies every step', () async {
      final storage = InstallStep('storage', mutations);

      final executable = InstallStep(
        'executable',
        mutations,
        prerequisites: {'storage'},
      );

      final service = InstallStep(
        'service',
        mutations,
        prerequisites: {'executable'},
      );

      final installer = HostInstaller(steps: [service, executable, storage]);

      final result = await installer.install();

      expect(result.is_successful, isTrue);

      expect(mutations, [
        'install:storage',
        'install:executable',
        'install:service',
      ]);

      expect(
        result.entries.map((entry) => entry.status),
        everyElement(HostInstallStepStatus.applied),
      );

      expect(storage.installed, isTrue);
      expect(executable.installed, isTrue);
      expect(service.installed, isTrue);

      // Preflight, immediate reinspection and post-execution verification.
      expect(storage.inspection_count, 3);
      expect(executable.inspection_count, 3);
      expect(service.inspection_count, 3);
    });

    test('verification never changes resource state', () async {
      final step = InstallStep('storage', mutations, installed: true);

      final installer = HostInstaller(steps: [step]);

      final verification = await installer.verify();

      expect(verification.is_satisfied, isTrue);
      expect(step.inspection_count, 1);
      expect(mutations, isEmpty);
    });

    test('repeated installation skips satisfied steps', () async {
      final step = InstallStep('storage', mutations);
      final installer = HostInstaller(steps: [step]);

      expect((await installer.install()).is_successful, isTrue);

      final repeated = await installer.install();

      expect(repeated.is_successful, isTrue);

      expect(repeated.entries.single.status, HostInstallStepStatus.unchanged);

      expect(mutations, ['install:storage']);
    });

    test('blocked preflight prevents all mutation', () async {
      final storage = InstallStep('storage', mutations);

      final service = InstallStep(
        'service',
        mutations,
        prerequisites: {'storage'},
        blocked: true,
      );

      final installer = HostInstaller(steps: [storage, service]);

      final result = await installer.install();

      expect(result.is_successful, isFalse);
      expect(mutations, isEmpty);

      expect(result.entries.map((entry) => entry.status), [
        HostInstallStepStatus.not_attempted,
        HostInstallStepStatus.blocked,
      ]);
    });

    test('execution does not trust a previously inspected plan', () async {
      final step = InstallStep('storage', mutations);
      final installer = HostInstaller(steps: [step]);

      final plan = await installer.plan();

      expect(plan.can_execute, isTrue);

      step.blocked = true;

      final result = await installer.install();

      expect(result.is_successful, isFalse);
      expect(mutations, isEmpty);

      expect(result.entries.single.status, HostInstallStepStatus.blocked);

      // The retained plan remains an immutable historical observation.
      expect(plan.can_execute, isTrue);
    });

    test('revalidates each step immediately before mutation', () async {
      final service = InstallStep(
        'service',
        mutations,
        prerequisites: {'storage'},
      );

      final storage = InstallStep(
        'storage',
        mutations,
        on_install: () async {
          service.blocked = true;
        },
      );

      final installer = HostInstaller(steps: [storage, service]);

      final result = await installer.install();

      expect(result.is_successful, isFalse);
      expect(mutations, ['install:storage']);

      expect(result.entries.map((entry) => entry.status), [
        HostInstallStepStatus.applied,
        HostInstallStepStatus.blocked,
      ]);
    });

    test('reports partial failure without rolling back prior steps', () async {
      final failure = StateError('Executable installation failed.');

      final storage = InstallStep('storage', mutations);

      final executable = InstallStep(
        'executable',
        mutations,
        prerequisites: {'storage'},
        on_install: () async {
          throw failure;
        },
      );

      final service = InstallStep(
        'service',
        mutations,
        prerequisites: {'executable'},
      );

      final installer = HostInstaller(steps: [storage, executable, service]);

      final result = await installer.install();

      expect(result.is_successful, isFalse);

      expect(result.entries.map((entry) => entry.status), [
        HostInstallStepStatus.applied,
        HostInstallStepStatus.failed,
        HostInstallStepStatus.not_attempted,
      ]);

      expect(result.entries[1].error, same(failure));
      expect(result.entries[1].stack_trace, isNotNull);

      expect(mutations, ['install:storage', 'install:executable']);

      expect(storage.installed, isTrue);
      expect(service.installed, isFalse);
    });

    test('failed verification prevents subsequent execution', () async {
      final storage = InstallStep('storage', mutations, apply_change: false);

      final service = InstallStep(
        'service',
        mutations,
        prerequisites: {'storage'},
      );

      final installer = HostInstaller(steps: [storage, service]);

      final result = await installer.install();

      expect(result.is_successful, isFalse);

      expect(result.entries.map((entry) => entry.status), [
        HostInstallStepStatus.failed,
        HostInstallStepStatus.not_attempted,
      ]);

      expect(mutations, ['install:storage']);
      expect(storage.installed, isFalse);
      expect(service.installed, isFalse);
    });

    test('repeated execution recovers from partial installation', () async {
      var should_fail = true;

      final storage = InstallStep('storage', mutations);

      final executable = InstallStep(
        'executable',
        mutations,
        prerequisites: {'storage'},
        on_install: () async {
          if (should_fail) {
            throw StateError('Temporary installation failure.');
          }
        },
      );

      final installer = HostInstaller(steps: [storage, executable]);

      expect((await installer.install()).is_successful, isFalse);

      should_fail = false;

      final retry = await installer.install();

      expect(retry.is_successful, isTrue);

      expect(retry.entries.map((entry) => entry.status), [
        HostInstallStepStatus.unchanged,
        HostInstallStepStatus.applied,
      ]);

      expect(mutations, [
        'install:storage',
        'install:executable',
        'install:executable',
      ]);
    });

    test('uninstalls in reverse dependency order', () async {
      final storage = InstallStep('storage', mutations, installed: true);

      final executable = InstallStep(
        'executable',
        mutations,
        prerequisites: {'storage'},
        installed: true,
      );

      final service = InstallStep(
        'service',
        mutations,
        prerequisites: {'executable'},
        installed: true,
      );

      final installer = HostInstaller(steps: [storage, executable, service]);

      final result = await installer.uninstall();

      expect(result.operation, HostInstallOperation.uninstall);
      expect(result.is_successful, isTrue);

      expect(mutations, [
        'uninstall:service',
        'uninstall:executable',
        'uninstall:storage',
      ]);

      expect(storage.installed, isFalse);
      expect(executable.installed, isFalse);
      expect(service.installed, isFalse);
    });

    test('uninstallation respects explicitly retained resources', () async {
      final data = InstallStep(
        'data',
        mutations,
        installed: true,
        retain_on_removal: true,
      );

      final service = InstallStep(
        'service',
        mutations,
        prerequisites: {'data'},
        installed: true,
      );

      final installer = HostInstaller(steps: [data, service]);

      final result = await installer.uninstall();

      expect(result.is_successful, isTrue);
      expect(mutations, ['uninstall:service']);
      expect(data.installed, isTrue);
      expect(service.installed, isFalse);

      expect(result.entries.last.status, HostInstallStepStatus.unchanged);
    });

    test('repeated uninstallation skips absent resources', () async {
      final step = InstallStep('storage', mutations, installed: true);

      final installer = HostInstaller(steps: [step]);

      expect((await installer.uninstall()).is_successful, isTrue);

      final repeated = await installer.uninstall();

      expect(repeated.is_successful, isTrue);

      expect(repeated.entries.single.status, HostInstallStepStatus.unchanged);

      expect(mutations, ['uninstall:storage']);
    });

    test('initial inspection failures prevent mutation', () async {
      final failure = StateError('Inspection failed.');

      final first = InstallStep('first', mutations);

      final second = InstallStep(
        'second',
        mutations,
        on_inspect: () {
          throw failure;
        },
      );

      final installer = HostInstaller(steps: [first, second]);

      await expectLater(installer.install(), throwsA(same(failure)));

      expect(mutations, isEmpty);

      // Inspection failure must release the operation guard.
      second.on_inspect = null;

      expect((await installer.install()).is_successful, isTrue);
    });

    test('rejects overlapping installer operations', () async {
      final entered = Completer<void>();
      final release = Completer<void>();

      final step = InstallStep(
        'storage',
        mutations,
        on_install: () async {
          entered.complete();
          await release.future;
        },
      );

      final installer = HostInstaller(steps: [step]);
      final installation = installer.install();

      try {
        await entered.future;

        await expectLater(installer.plan(), throwsStateError);

        await expectLater(installer.verify(), throwsStateError);

        await expectLater(installer.install(), throwsStateError);

        await expectLater(installer.uninstall(), throwsStateError);
      } finally {
        release.complete();
        await installation;
      }

      expect((await installation).is_successful, isTrue);
      expect((await installer.verify()).is_satisfied, isTrue);
    });

    test('retains immutable plans and execution results', () async {
      final step = InstallStep('storage', mutations);
      final installer = HostInstaller(steps: [step]);

      final plan = await installer.plan();
      final result = await installer.install();

      expect(() => plan.entries.clear(), throwsUnsupportedError);

      expect(() => result.entries.clear(), throwsUnsupportedError);

      expect(plan.is_satisfied, isFalse);
      expect(result.is_successful, isTrue);
    });
  });
}

/// Synthetic installation contribution retaining observable resource state.
///
/// Supports controlled inspection failures, execution failures,
/// retained resources and delayed execution without native I/O.
final class InstallStep implements HostInstallStep {
  InstallStep(
    this.id,
    this.mutations, {
    this.prerequisites = const {},
    this.installed = false,
    this.blocked = false,
    this.apply_change = true,
    this.retain_on_removal = false,
    this.on_inspect,
    this.on_install,
  });

  @override
  final String id;

  @override
  final Set<String> prerequisites;

  final List<String> mutations;

  bool installed;
  bool blocked;
  final bool apply_change;
  final bool retain_on_removal;

  void Function()? on_inspect;
  final Future<void> Function()? on_install;

  int inspection_count = 0;

  @override
  Future<HostInstallInspection> inspect(HostInstallOperation operation) async {
    inspection_count++;
    on_inspect?.call();

    if (blocked) {
      return HostInstallInspection(
        disposition: HostInstallDisposition.blocked,
        description: '$id is blocked.',
      );
    }

    final satisfied = switch (operation) {
      HostInstallOperation.install => installed,
      HostInstallOperation.uninstall => !installed || retain_on_removal,
    };

    return HostInstallInspection(
      disposition: satisfied
          ? HostInstallDisposition.satisfied
          : HostInstallDisposition.change_required,
      description: satisfied ? '$id is satisfied.' : '$id requires a change.',
    );
  }

  @override
  Future<void> install() async {
    mutations.add('install:$id');

    await on_install?.call();

    if (apply_change) {
      installed = true;
    }
  }

  @override
  Future<void> uninstall() async {
    mutations.add('uninstall:$id');

    if (apply_change && !retain_on_removal) {
      installed = false;
    }
  }
}
