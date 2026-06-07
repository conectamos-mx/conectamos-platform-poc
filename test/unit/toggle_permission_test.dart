import 'package:flutter_test/flutter_test.dart';
import 'package:conectamos_platform/core/utils/toggle_permission.dart';

// ── Test data ────────────────────────────────────────────────────────────────

const _prereqs = <String, String>{
  'flows.manage': 'flows.view',
  'operators.manage': 'operators.view',
};

const _labels = <String, String>{
  'flows.view': 'Ver flujos',
  'flows.manage': 'Gestionar flujos',
  'operators.view': 'Ver operadores',
  'operators.manage': 'Gestionar operadores',
  'reports.view': 'Ver reportes',
};

// Transitive chain: C depends on B, B depends on A
const _transitivePrereqs = <String, String>{
  'x.B': 'x.A',
  'x.C': 'x.B',
};

const _transitiveLabels = <String, String>{
  'x.A': 'Permiso A',
  'x.B': 'Permiso B',
  'x.C': 'Permiso C',
};

// ── Golden tests ─────────────────────────────────────────────────────────────

void main() {
  group('toggle — golden characterization of current behavior', () {
    test('activate action with direct prerequisite: activates prereq + cascade message', () {
      final grants = {'flows.view': false, 'flows.manage': false};
      final result = togglePermission(
        currentGrants: grants,
        module: 'flows',
        action: 'manage',
        prerequisites: _prereqs,
        labels: _labels,
      );

      expect(result.grants['flows.manage'], isTrue);
      expect(result.grants['flows.view'], isTrue);
      expect(result.cascadeMessages, hasLength(1));
      expect(result.cascadeMessages.first, contains('Ver flujos'));
      expect(result.cascadeMessages.first, contains('Gestionar flujos'));
    });

    test('activate action whose prereq is already active: no cascade message', () {
      final grants = {'flows.view': true, 'flows.manage': false};
      final result = togglePermission(
        currentGrants: grants,
        module: 'flows',
        action: 'manage',
        prerequisites: _prereqs,
        labels: _labels,
      );

      expect(result.grants['flows.manage'], isTrue);
      expect(result.grants['flows.view'], isTrue);
      expect(result.cascadeMessages, isEmpty);
    });

    test('deactivate prerequisite with active dependent: deactivates dependent + cascade message', () {
      final grants = {'flows.view': true, 'flows.manage': true};
      final result = togglePermission(
        currentGrants: grants,
        module: 'flows',
        action: 'view',
        prerequisites: _prereqs,
        labels: _labels,
      );

      expect(result.grants['flows.view'], isFalse);
      expect(result.grants['flows.manage'], isFalse);
      expect(result.cascadeMessages, hasLength(1));
      expect(result.cascadeMessages.first, contains('Gestionar flujos'));
      expect(result.cascadeMessages.first, contains('Ver flujos'));
    });

    test('deactivate prerequisite with inactive dependent: no cascade message', () {
      final grants = {'flows.view': true, 'flows.manage': false};
      final result = togglePermission(
        currentGrants: grants,
        module: 'flows',
        action: 'view',
        prerequisites: _prereqs,
        labels: _labels,
      );

      expect(result.grants['flows.view'], isFalse);
      expect(result.grants['flows.manage'], isFalse);
      expect(result.cascadeMessages, isEmpty);
    });

    test('toggle permission with no relations: no cascade', () {
      final grants = {'reports.view': false};
      final result = togglePermission(
        currentGrants: grants,
        module: 'reports',
        action: 'view',
        prerequisites: _prereqs,
        labels: _labels,
      );

      expect(result.grants['reports.view'], isTrue);
      expect(result.cascadeMessages, isEmpty);
    });

    test('idempotency: double toggle returns to original state', () {
      final original = {'flows.view': true, 'flows.manage': true};
      final first = togglePermission(
        currentGrants: original,
        module: 'flows',
        action: 'view',
        prerequisites: _prereqs,
        labels: _labels,
      );
      // After first toggle: both false
      expect(first.grants['flows.view'], isFalse);
      expect(first.grants['flows.manage'], isFalse);

      final second = togglePermission(
        currentGrants: first.grants,
        module: 'flows',
        action: 'view',
        prerequisites: _prereqs,
        labels: _labels,
      );
      // After second toggle: view true, manage stays false (no auto-reactivate)
      expect(second.grants['flows.view'], isTrue);
      expect(second.grants['flows.manage'], isFalse);
    });

    test('cascade messages use labels, not raw keys', () {
      final grants = {'flows.view': false, 'flows.manage': false};
      final result = togglePermission(
        currentGrants: grants,
        module: 'flows',
        action: 'manage',
        prerequisites: _prereqs,
        labels: _labels,
      );

      final msg = result.cascadeMessages.first;
      expect(msg, contains('Ver flujos'));
      expect(msg, isNot(contains('"flows.view"')));
    });

    test('cascade message falls back to key when label missing', () {
      final grants = {'foo.bar': false, 'foo.baz': false};
      final prereqs = {'foo.baz': 'foo.bar'};
      final result = togglePermission(
        currentGrants: grants,
        module: 'foo',
        action: 'baz',
        prerequisites: prereqs,
        labels: const {},
      );

      final msg = result.cascadeMessages.first;
      expect(msg, contains('foo.bar'));
      expect(msg, contains('foo.baz'));
    });

    // ── Transitive cases: document ONE-LEVEL limit ───────────────────────

    test('transitive DEACTIVATE: A→B→C, deactivate A deactivates B but NOT C', () {
      final grants = {'x.A': true, 'x.B': true, 'x.C': true};
      final result = togglePermission(
        currentGrants: grants,
        module: 'x',
        action: 'A',
        prerequisites: _transitivePrereqs,
        labels: _transitiveLabels,
      );

      expect(result.grants['x.A'], isFalse);
      expect(result.grants['x.B'], isFalse, reason: 'direct dependent deactivated');
      // C is NOT deactivated — one-level limit. C is now orphan (depends on B which is off).
      expect(result.grants['x.C'], isTrue, reason: 'transitive dependent NOT deactivated (one-level limit)');
      expect(result.cascadeMessages, hasLength(1));
      expect(result.cascadeMessages.first, contains('Permiso B'));
    });

    test('transitive ACTIVATE: A→B→C, activate C activates B but NOT A', () {
      final grants = {'x.A': false, 'x.B': false, 'x.C': false};
      final result = togglePermission(
        currentGrants: grants,
        module: 'x',
        action: 'C',
        prerequisites: _transitivePrereqs,
        labels: _transitiveLabels,
      );

      expect(result.grants['x.C'], isTrue);
      expect(result.grants['x.B'], isTrue, reason: 'direct prerequisite activated');
      // A is NOT activated — one-level limit. B is now active without its prereq A.
      expect(result.grants['x.A'], isFalse, reason: 'transitive prerequisite NOT activated (one-level limit)');
      expect(result.cascadeMessages, hasLength(1));
      expect(result.cascadeMessages.first, contains('Permiso B'));
    });
  });
}
