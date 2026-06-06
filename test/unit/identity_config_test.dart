import 'package:flutter_test/flutter_test.dart';
import 'package:conectamos_platform/core/utils/identity_config.dart';

void main() {
  // ── getIdentityConfig ─────────────────────────────────────────────────────

  group('getIdentityConfig', () {
    test('returns config for MX', () {
      final cfg = getIdentityConfig('MX');
      expect(cfg, isNotNull);
      expect(cfg!.type, 'curp');
    });

    test('returns config for US', () {
      final cfg = getIdentityConfig('US');
      expect(cfg, isNotNull);
      expect(cfg!.type, 'ssn');
    });

    test('is case-insensitive', () {
      expect(getIdentityConfig('mx'), isNotNull);
      expect(getIdentityConfig('mx')!.type, 'curp');
      expect(getIdentityConfig('Mx')!.type, 'curp');
    });

    test('returns null for unknown country', () {
      expect(getIdentityConfig('ZZ'), isNull);
    });

    test('returns config for all defined countries', () {
      for (final code in ['MX', 'US', 'CO', 'GT', 'HN', 'SV', 'ES']) {
        expect(getIdentityConfig(code), isNotNull, reason: 'Missing config for $code');
      }
    });
  });

  // ── IdentityConfig.validate — MX CURP ─────────────────────────────────────

  group('IdentityConfig.validate — MX CURP', () {
    late IdentityConfig curp;
    setUp(() => curp = kIdentityConfig['MX']!);

    test('accepts valid CURP (example from config)', () {
      expect(curp.validate('LOOA530101HTCPBN02'), isTrue);
    });

    test('accepts lowercase input (uppercased internally)', () {
      expect(curp.validate('looa530101htcpbn02'), isTrue);
    });

    test('rejects too-short string', () {
      expect(curp.validate('LOOA5301'), isFalse);
    });

    test('rejects invalid characters in letter positions', () {
      expect(curp.validate('1234530101HTCPBN02'), isFalse);
    });

    test('rejects empty string', () {
      expect(curp.validate(''), isFalse);
    });
  });

  // ── IdentityConfig.validate — US SSN ──────────────────────────────────────

  group('IdentityConfig.validate — US SSN', () {
    late IdentityConfig ssn;
    setUp(() => ssn = kIdentityConfig['US']!);

    test('accepts SSN with dashes', () {
      expect(ssn.validate('123-45-6789'), isTrue);
    });

    test('accepts SSN without dashes', () {
      expect(ssn.validate('123456789'), isTrue);
    });

    test('rejects too few digits', () {
      expect(ssn.validate('12345678'), isFalse);
    });

    test('rejects letters', () {
      expect(ssn.validate('ABC-DE-FGHI'), isFalse);
    });
  });

  // ── IdentityConfig.validate — CO Cedula ───────────────────────────────────

  group('IdentityConfig.validate — CO Cedula', () {
    late IdentityConfig cedula;
    setUp(() => cedula = kIdentityConfig['CO']!);

    test('accepts 10-digit cedula', () {
      expect(cedula.validate('1234567890'), isTrue);
    });

    test('accepts 6-digit cedula', () {
      expect(cedula.validate('123456'), isTrue);
    });

    test('rejects 5-digit (too short)', () {
      expect(cedula.validate('12345'), isFalse);
    });

    test('rejects 11-digit (too long)', () {
      expect(cedula.validate('12345678901'), isFalse);
    });
  });

  // ── IdentityConfig.validate — GT DPI ──────────────────────────────────────

  group('IdentityConfig.validate — GT DPI', () {
    late IdentityConfig dpi;
    setUp(() => dpi = kIdentityConfig['GT']!);

    test('accepts 13-digit DPI', () {
      expect(dpi.validate('1234567890123'), isTrue);
    });

    test('rejects 12-digit (too short)', () {
      expect(dpi.validate('123456789012'), isFalse);
    });
  });

  // ── IdentityConfig.validate — HN DNI ──────────────────────────────────────

  group('IdentityConfig.validate — HN DNI', () {
    late IdentityConfig dni;
    setUp(() => dni = kIdentityConfig['HN']!);

    test('accepts 13-digit DNI', () {
      expect(dni.validate('0101199912345'), isTrue);
    });

    test('rejects letters', () {
      expect(dni.validate('010119991234A'), isFalse);
    });
  });

  // ── IdentityConfig.validate — SV DUI ──────────────────────────────────────

  group('IdentityConfig.validate — SV DUI', () {
    late IdentityConfig dui;
    setUp(() => dui = kIdentityConfig['SV']!);

    test('accepts DUI with dash', () {
      expect(dui.validate('12345678-9'), isTrue);
    });

    test('accepts DUI without dash', () {
      expect(dui.validate('123456789'), isTrue);
    });

    test('rejects too-short DUI', () {
      expect(dui.validate('1234567'), isFalse);
    });
  });

  // ── IdentityConfig.validate — ES NIF/NIE ──────────────────────────────────

  group('IdentityConfig.validate — ES NIF/NIE', () {
    late IdentityConfig nif;
    setUp(() => nif = kIdentityConfig['ES']!);

    test('accepts valid NIF', () {
      expect(nif.validate('12345678A'), isTrue);
    });

    test('accepts NIE format', () {
      expect(nif.validate('X1234567A'), isTrue);
    });

    test('rejects without trailing letter', () {
      expect(nif.validate('123456789'), isFalse);
    });
  });
}
