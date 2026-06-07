import 'package:flutter_test/flutter_test.dart';
import 'package:conectamos_platform/core/utils/execution_labels.dart';

void main() {
  group('executionEventLabel', () {
    final expected = {
      'flujo_iniciado': 'Flujo iniciado',
      'flujo_completado': 'Flujo completado',
      'flujo_retomado': 'Flujo retomado',
      'campo_capturado': 'Campo capturado',
      'campo_rechazado': 'Campo rechazado',
      'worker_escaló': 'Worker escaló',
      'flujo_abandonado': 'Flujo abandonado',
      'supervisor_intervino': 'Supervisor intervino',
      'flujo_pausado': 'Flujo pausado',
    };
    for (final e in expected.entries) {
      test('${e.key} → ${e.value}', () {
        expect(executionEventLabel(e.key), e.value);
      });
    }
    test('unknown falls back to raw', () {
      expect(executionEventLabel('custom_event'), 'custom_event');
    });
  });

  group('executionStatusLabel', () {
    final expected = {
      'completed': 'Completado',
      'in_progress': 'En curso',
      'active': 'En curso',
      'pending': 'Pendiente',
      'pending_dashboard': 'Pendiente de revisión',
      'pending_review': 'Pendiente de revisión',
      'paused': 'Pausado',
      'abandoned': 'Abandonado',
      'escalated': 'Escalado',
      'cancelled': 'Cancelado',
      'failed': 'Fallido',
      'error': 'Fallido',
    };
    for (final e in expected.entries) {
      test('${e.key} → ${e.value}', () {
        expect(executionStatusLabel(e.key), e.value);
      });
    }
    test('unknown falls back to raw', () {
      expect(executionStatusLabel('xyz'), 'xyz');
    });
  });

  group('resolveFieldValue', () {
    test('number → value_numeric', () {
      expect(resolveFieldValue({'value_numeric': 42}, 'number'), '42');
    });
    test('number missing → —', () {
      expect(resolveFieldValue({}, 'number'), '—');
    });

    test('media with jsonb url', () {
      expect(
        resolveFieldValue({
          'value_jsonb': {'url': 'https://img.png'},
        }, 'media'),
        'https://img.png',
      );
    });
    test('photo with jsonb url', () {
      expect(
        resolveFieldValue({
          'value_jsonb': {'url': 'https://photo.jpg'},
        }, 'photo'),
        'https://photo.jpg',
      );
    });
    test('media fallback to value_media_url', () {
      expect(
        resolveFieldValue({'value_media_url': 'https://fallback.png'}, 'media'),
        'https://fallback.png',
      );
    });
    test('media missing → —', () {
      expect(resolveFieldValue({}, 'media'), '—');
    });

    test('location with lat/lng', () {
      expect(
        resolveFieldValue({
          'value_jsonb': {'lat': 19.4, 'lng': -99.1},
        }, 'location'),
        '19.4, -99.1',
      );
    });
    test('location with latitude/longitude', () {
      expect(
        resolveFieldValue({
          'value_jsonb': {'latitude': 20.0, 'longitude': -100.0},
        }, 'location'),
        '20.0, -100.0',
      );
    });
    test('location fallback to value_text', () {
      expect(
        resolveFieldValue({'value_text': 'CDMX'}, 'location'),
        'CDMX',
      );
    });
    test('location missing → —', () {
      expect(resolveFieldValue({}, 'location'), '—');
    });

    test('text (default) → value_text', () {
      expect(resolveFieldValue({'value_text': 'hello'}, 'text'), 'hello');
    });
    test('text missing → —', () {
      expect(resolveFieldValue({}, 'text'), '—');
    });
  });

  group('groupExecutionEvents', () {
    test('groups consecutive same-type events', () {
      final events = [
        {'type': 'a', 'id': '1'},
        {'type': 'a', 'id': '2'},
        {'type': 'b', 'id': '3'},
        {'type': 'a', 'id': '4'},
      ];
      final groups = groupExecutionEvents(events);
      expect(groups.length, 3);
      expect(groups[0].type, 'a');
      expect(groups[0].items.length, 2);
      expect(groups[1].type, 'b');
      expect(groups[1].items.length, 1);
      expect(groups[2].type, 'a');
      expect(groups[2].items.length, 1);
    });

    test('empty list → empty result', () {
      expect(groupExecutionEvents([]), isEmpty);
    });

    test('falls back to event_type key', () {
      final events = [
        {'event_type': 'x'},
      ];
      final groups = groupExecutionEvents(events);
      expect(groups[0].type, 'x');
    });
  });
}
