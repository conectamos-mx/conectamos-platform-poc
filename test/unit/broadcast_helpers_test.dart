import 'package:flutter_test/flutter_test.dart';
import 'package:conectamos_platform/core/utils/broadcast_helpers.dart';

void main() {
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
}
