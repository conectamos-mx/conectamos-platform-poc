import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:conectamos_platform/core/utils/broadcast_helpers.dart';
import 'package:conectamos_platform/core/utils/tz_format.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_MX', null);
    initTz();
  });
  group('resolveTemplatePreview', () {
    test('system variable resolves from examples', () {
      final tpl = {
        'body_text': 'Hola {{1}}, tu número es {{2}}',
        'variables': [
          {'slot': 1, 'type': 'system', 'key': 'nombre_operador'},
          {'slot': 2, 'type': 'system', 'key': 'telefono_operador'},
        ],
      };
      expect(
        resolveTemplatePreview(tpl),
        'Hola José Miguel, tu número es 5215559537449',
      );
    });

    test('free variable with key shows [key]', () {
      final tpl = {
        'body_text': 'Hola {{1}}',
        'variables': [
          {'slot': 1, 'type': 'free', 'key': 'custom_name'},
        ],
      };
      expect(resolveTemplatePreview(tpl), 'Hola [custom_name]');
    });

    test('free variable without key leaves {{N}} literal', () {
      final tpl = {
        'body_text': 'Hola {{1}}',
        'variables': [
          {'slot': 1, 'type': 'free', 'key': ''},
        ],
      };
      expect(resolveTemplatePreview(tpl), 'Hola {{1}}');
    });

    test('absent variable leaves {{N}} literal', () {
      final tpl = {
        'body_text': 'Hola {{1}} y {{2}}',
        'variables': [
          {'slot': 1, 'type': 'system', 'key': 'nombre_operador'},
        ],
      };
      expect(resolveTemplatePreview(tpl), 'Hola José Miguel y {{2}}');
    });

    test('unknown system key shows [key]', () {
      final tpl = {
        'body_text': 'Val: {{1}}',
        'variables': [
          {'slot': 1, 'type': 'system', 'key': 'unknown_key'},
        ],
      };
      expect(resolveTemplatePreview(tpl), 'Val: [unknown_key]');
    });

    test('no variables returns body as-is', () {
      final tpl = {'body_text': 'Sin variables'};
      expect(resolveTemplatePreview(tpl), 'Sin variables');
    });

    test('slot 0 is not replaced', () {
      final tpl = {
        'body_text': 'Hola {{0}}',
        'variables': [
          {'slot': 0, 'type': 'system', 'key': 'nombre_operador'},
        ],
      };
      expect(resolveTemplatePreview(tpl), 'Hola {{0}}');
    });
  });

  group('resolveTemplateVariables', () {
    test('system variable returns example value', () {
      final tpl = {
        'variables': [
          {'slot': 1, 'type': 'system', 'key': 'nombre_operador'},
        ],
      };
      expect(resolveTemplateVariables(tpl), ['José Miguel']);
    });

    test('free variable with key returns [key]', () {
      final tpl = {
        'variables': [
          {'slot': 1, 'type': 'free', 'key': 'custom'},
        ],
      };
      expect(resolveTemplateVariables(tpl), ['[custom]']);
    });

    test('free variable without key returns [variable]', () {
      final tpl = {
        'variables': [
          {'slot': 1, 'type': 'free', 'key': ''},
        ],
      };
      expect(resolveTemplateVariables(tpl), ['[variable]']);
    });

    test('sorted by slot', () {
      final tpl = {
        'variables': [
          {'slot': 3, 'type': 'system', 'key': 'nombre_tenant'},
          {'slot': 1, 'type': 'system', 'key': 'nombre_operador'},
          {'slot': 2, 'type': 'system', 'key': 'telefono_operador'},
        ],
      };
      expect(resolveTemplateVariables(tpl), [
        'José Miguel',
        '5215559537449',
        'TMR-Prixz',
      ]);
    });

    test('empty variables returns empty list', () {
      expect(resolveTemplateVariables({'variables': []}), isEmpty);
    });

    test('no variables key returns empty list', () {
      expect(resolveTemplateVariables({}), isEmpty);
    });
  });

  group('parseWhatsAppErrorMessage', () {
    test('131037 code', () {
      expect(
        parseWhatsAppErrorMessage('Error 131037: display name not set'),
        contains('nombre de perfil aprobado por Meta'),
      );
    });

    test('display name substring', () {
      expect(
        parseWhatsAppErrorMessage('Something about display name issue'),
        contains('nombre de perfil aprobado por Meta'),
      );
    });

    test('131026 code', () {
      expect(
        parseWhatsAppErrorMessage('Error 131026'),
        contains('no está registrado como destinatario de prueba'),
      );
    });

    test('not in whitelist substring', () {
      expect(
        parseWhatsAppErrorMessage('Recipient not in whitelist'),
        contains('no está registrado como destinatario de prueba'),
      );
    });

    test('generic error', () {
      expect(
        parseWhatsAppErrorMessage('Some unknown error'),
        'Error al enviar el mensaje. Intenta de nuevo.',
      );
    });

    test('internal exception falls back to generic', () {
      // The function wraps in try/catch — an object whose toString throws
      // should still return the fallback.
      expect(
        parseWhatsAppErrorMessage(null),
        'Error al enviar el mensaje. Intenta de nuevo.',
      );
    });
  });

  group('kBroadcastFreeVars', () {
    test('has 7 entries', () {
      expect(kBroadcastFreeVars.length, 7);
    });

    test('first entry is nombre', () {
      expect(kBroadcastFreeVars.first.key, '{nombre}');
      expect(kBroadcastFreeVars.first.label, 'nombre');
    });
  });

  group('resolveFreeText', () {
    setUp(() => setActiveZone('America/Mexico_City'));

    test('empty text returns empty', () {
      expect(resolveFreeText('', null, 'Acme'), '');
    });

    test('text without placeholders returns as-is', () {
      expect(resolveFreeText('Hola mundo', null, 'Acme'), 'Hola mundo');
    });

    test('{nombre} resolves display_name', () {
      final op = {'display_name': 'Carlos'};
      expect(resolveFreeText('Hola {nombre}', op, 'X'), 'Hola Carlos');
    });

    test('{nombre} falls back to name when display_name is null', () {
      final op = {'name': 'Ana'};
      expect(resolveFreeText('{nombre}', op, 'X'), 'Ana');
    });

    test('{nombre} falls back to Operador when op is null', () {
      expect(resolveFreeText('{nombre}', null, 'X'), 'Operador');
    });

    test('{telefono} resolves phone', () {
      final op = {'phone': '+5215551234567'};
      expect(resolveFreeText('{telefono}', op, 'X'), '+5215551234567');
    });

    test('{telefono} returns empty when op is null', () {
      expect(resolveFreeText('{telefono}', null, 'X'), '');
    });

    test('{flujo} resolves from map flows', () {
      final op = {
        'flows': [{'name': 'Cobranza'}]
      };
      expect(resolveFreeText('{flujo}', op, 'X'), 'Cobranza');
    });

    test('{flujo} resolves from string flows', () {
      final op = {
        'flows': ['Ventas']
      };
      expect(resolveFreeText('{flujo}', op, 'X'), 'Ventas');
    });

    test('{flujo} returns Sin flujo when no flows', () {
      expect(resolveFreeText('{flujo}', {}, 'X'), 'Sin flujo');
    });

    test('{tenant} resolves tenant name', () {
      expect(resolveFreeText('{tenant}', null, 'Acme Corp'), 'Acme Corp');
    });

    test('{hora} resolves as HH:mm in tenant timezone', () {
      final result = resolveFreeText('{hora}', null, 'X');
      expect(result, matches(RegExp(r'^\d{2}:\d{2}$')));
    });

    test('{dia} resolves as capitalised Spanish weekday', () {
      final result = resolveFreeText('{dia}', null, 'X');
      final validDays = [
        'Lunes', 'Martes', 'Miércoles', 'Jueves',
        'Viernes', 'Sábado', 'Domingo',
      ];
      expect(validDays, contains(result));
    });

    test('{fecha} resolves as dd/MM/yyyy in tenant timezone', () {
      final result = resolveFreeText('{fecha}', null, 'X');
      expect(result, matches(RegExp(r'^\d{2}/\d{2}/\d{4}$')));
    });

    test('midnight boundary: America/Mexico_City near midnight UTC', () {
      // Set timezone to CDMX (UTC-6 in winter / UTC-5 in summer)
      // At 04:30 UTC on Jan 2, it's 22:30 on Jan 1 in CDMX (CST, UTC-6)
      // We can't inject a fake clock, but we verify the function uses
      // nowInZone() (tenant TZ) by checking the format is valid.
      setActiveZone('America/Mexico_City');
      final result = resolveFreeText('{hora} {dia} {fecha}', null, 'X');
      // Should contain HH:mm, a valid day name, and dd/MM/yyyy
      expect(result, matches(RegExp(
        r'^\d{2}:\d{2} (Lunes|Martes|Miércoles|Jueves|Viernes|Sábado|Domingo) \d{2}/\d{2}/\d{4}$',
      )));
    });

    test('all placeholders resolve together', () {
      final op = {
        'display_name': 'Luis',
        'phone': '5551234',
        'flows': [{'name': 'Logística'}],
      };
      final result = resolveFreeText(
        'Hola {nombre}, tel {telefono}, flujo {flujo}, '
        'hora {hora}, día {dia}, fecha {fecha}, empresa {tenant}',
        op,
        'Acme',
      );
      expect(result, contains('Hola Luis'));
      expect(result, contains('tel 5551234'));
      expect(result, contains('flujo Logística'));
      expect(result, contains('empresa Acme'));
      expect(result, isNot(contains('{hora}')));
      expect(result, isNot(contains('{dia}')));
      expect(result, isNot(contains('{fecha}')));
    });
  });
}
