import 'package:flutter_test/flutter_test.dart';
import 'package:conectamos_platform/core/providers/tenant_provider.dart';

void main() {
  // ── TenantInfo.fromMap — displayName fallback chain ───────────────────────

  group('TenantInfo.fromMap — displayName fallback', () {
    test('uses display_name when present', () {
      final t = TenantInfo.fromMap({
        'id': 'abc',
        'slug': 'acme',
        'display_name': 'Acme Corp',
        'name': 'acme-name',
      });
      expect(t.displayName, 'Acme Corp');
    });

    test('falls back to name when display_name is null', () {
      final t = TenantInfo.fromMap({
        'id': 'abc',
        'slug': 'acme',
        'name': 'acme-name',
      });
      expect(t.displayName, 'acme-name');
    });

    test('falls back to slug when display_name and name are both null', () {
      final t = TenantInfo.fromMap({
        'id': 'abc',
        'slug': 'acme-slug',
      });
      expect(t.displayName, 'acme-slug');
    });

    test('falls back to empty string when all three are null', () {
      final t = TenantInfo.fromMap({'id': 'abc'});
      expect(t.displayName, '');
    });
  });

  // ── TenantInfo.fromMap — field extraction ─────────────────────────────────

  group('TenantInfo.fromMap — field extraction', () {
    test('trims id whitespace', () {
      final t = TenantInfo.fromMap({
        'id': '  abc-123  ',
        'slug': 's',
      });
      expect(t.id, 'abc-123');
    });

    test('extracts slug', () {
      final t = TenantInfo.fromMap({
        'id': 'x',
        'slug': 'my-slug',
      });
      expect(t.slug, 'my-slug');
    });

    test('extracts logoUrl when present', () {
      final t = TenantInfo.fromMap({
        'id': 'x',
        'slug': 's',
        'logo_url': 'https://example.com/logo.png',
      });
      expect(t.logoUrl, 'https://example.com/logo.png');
    });

    test('logoUrl is null when missing', () {
      final t = TenantInfo.fromMap({'id': 'x', 'slug': 's'});
      expect(t.logoUrl, isNull);
    });
  });

  // ── TenantInfo.fromMap — empty / minimal map ──────────────────────────────

  group('TenantInfo.fromMap — edge cases', () {
    test('handles completely empty map', () {
      final t = TenantInfo.fromMap({});
      expect(t.id, '');
      expect(t.slug, '');
      expect(t.displayName, '');
      expect(t.logoUrl, isNull);
    });

    test('id defaults to empty string when null', () {
      final t = TenantInfo.fromMap({'id': null, 'slug': 's'});
      expect(t.id, '');
    });
  });

  // ── TenantState ───────────────────────────────────────────────────────────

  group('TenantState', () {
    test('default state has empty list and null active', () {
      const s = TenantState();
      expect(s.all, isEmpty);
      expect(s.active, isNull);
    });

    test('withActive returns new state with active tenant', () {
      const tenant = TenantInfo(
          id: '1', slug: 's', displayName: 'T');
      const s = TenantState();
      final s2 = s.withActive(tenant);
      expect(s2.active?.id, '1');
      expect(s2.all, isEmpty); // all unchanged
    });

    test('withAll returns new state with list and active', () {
      const t1 = TenantInfo(id: '1', slug: 's1', displayName: 'T1');
      const t2 = TenantInfo(id: '2', slug: 's2', displayName: 'T2');
      const s = TenantState();
      final s2 = s.withAll([t1, t2], t1);
      expect(s2.all.length, 2);
      expect(s2.active?.id, '1');
    });
  });
}
