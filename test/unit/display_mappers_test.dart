import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:conectamos_platform/core/utils/display_mappers.dart';
import 'package:conectamos_platform/core/theme/colors.dart';
import 'package:conectamos_platform/shared/widgets/app_badge.dart';

void main() {
  group('initials', () {
    test('single word returns first letter', () {
      expect(initials('Ana'), 'A');
    });

    test('two words returns first + last initials', () {
      expect(initials('Ana Lopez'), 'AL');
    });

    test('three+ words returns first + last initials', () {
      expect(initials('Ana Maria Lopez'), 'AL');
    });

    test('empty string returns ?', () {
      expect(initials(''), '?');
    });

    test('whitespace-only returns ?', () {
      expect(initials('   '), '?');
    });

    test('multiple spaces between words', () {
      expect(initials('Ana   Lopez'), 'AL');
    });

    test('lowercase is uppercased', () {
      expect(initials('ana lopez'), 'AL');
    });
  });

  group('hexColor', () {
    test('valid 6-digit hex with #', () {
      expect(hexColor('#3ABFAD'), const Color(0xFF3ABFAD));
    });

    test('valid 6-digit hex without #', () {
      expect(hexColor('3ABFAD'), const Color(0xFF3ABFAD));
    });

    test('null returns fallback', () {
      expect(hexColor(null), AppColors.ctText3);
    });

    test('malformed hex returns fallback', () {
      expect(hexColor('xyz'), AppColors.ctText3);
    });

    test('too short returns fallback', () {
      expect(hexColor('#FFF'), AppColors.ctText3);
    });

    test('empty string returns fallback', () {
      expect(hexColor(''), AppColors.ctText3);
    });
  });

  group('mediaFallback', () {
    test('image', () {
      expect(mediaFallback('image'), contains('Imagen'));
    });

    test('audio', () {
      expect(mediaFallback('audio'), contains('Nota de voz'));
    });

    test('unknown type falls back to Archivo', () {
      expect(mediaFallback('unknown'), contains('Archivo'));
    });
  });

  group('mediaIcon', () {
    test('image returns image_outlined', () {
      expect(mediaIcon('image'), Icons.image_outlined);
    });

    test('video returns videocam_outlined', () {
      expect(mediaIcon('video'), Icons.videocam_outlined);
    });

    test('audio returns mic_outlined', () {
      expect(mediaIcon('audio'), Icons.mic_outlined);
    });

    test('document returns attach_file_rounded', () {
      expect(mediaIcon('document'), Icons.attach_file_rounded);
    });

    test('unknown returns attach_file_rounded', () {
      expect(mediaIcon('unknown'), Icons.attach_file_rounded);
    });
  });

  group('mediaLabel', () {
    test('image', () => expect(mediaLabel('image'), 'Imagen'));
    test('video', () => expect(mediaLabel('video'), 'Video'));
    test('audio', () => expect(mediaLabel('audio'), 'Audio'));
    test('document', () => expect(mediaLabel('document'), 'Archivo'));
    test('unknown', () => expect(mediaLabel('unknown'), 'Adjunto'));
  });

  group('statusBadgeInfo', () {
    test('active returns Activo + ok', () {
      final r = statusBadgeInfo('active');
      expect(r.label, 'Activo');
      expect(r.variant, AppBadgeVariant.ok);
    });

    test('null returns Inactivo + neutral', () {
      final r = statusBadgeInfo(null);
      expect(r.label, 'Inactivo');
      expect(r.variant, AppBadgeVariant.neutral);
    });

    test('unknown returns Inactivo + neutral', () {
      final r = statusBadgeInfo('suspended');
      expect(r.label, 'Inactivo');
      expect(r.variant, AppBadgeVariant.neutral);
    });
  });

  group('telegramBadgeVariant', () {
    test('linked returns teal', () {
      expect(telegramBadgeVariant('linked'), AppBadgeVariant.teal);
    });

    test('pending returns warn', () {
      expect(telegramBadgeVariant('pending'), AppBadgeVariant.warn);
    });

    test('expired returns warn', () {
      expect(telegramBadgeVariant('expired'), AppBadgeVariant.warn);
    });
  });

  group('telegramBadgeLabel', () {
    test('linked', () {
      expect(telegramBadgeLabel('linked'), 'Telegram vinculado');
    });

    test('pending', () {
      expect(telegramBadgeLabel('pending'), 'Vinculacion pendiente');
    });

    test('expired', () {
      expect(telegramBadgeLabel('expired'), 'Invitacion expirada');
    });
  });

  group('msgBody', () {
    test('returns raw_body when present', () {
      expect(msgBody({'raw_body': 'Hola', 'message_type': 'text'}), 'Hola');
    });

    test('falls back to mediaFallback when raw_body is null', () {
      final result = msgBody({'message_type': 'image'});
      expect(result, contains('Imagen'));
    });

    test('falls back to mediaFallback when raw_body is empty', () {
      final result = msgBody({'raw_body': '', 'message_type': 'video'});
      expect(result, contains('Video'));
    });
  });

  group('outboundSenderName', () {
    test('returns from_name when present', () {
      expect(outboundSenderName({'from_name': 'Carlos'}), 'Carlos');
    });

    test('returns AI Worker for ai_worker origin', () {
      expect(outboundSenderName({'origin': 'ai_worker'}), 'AI Worker');
    });

    test('returns Agente when sent_by_user_id present', () {
      expect(
        outboundSenderName({'sent_by_user_id': 'abc123'}),
        'Agente',
      );
    });

    test('returns Supervisor as final fallback', () {
      expect(outboundSenderName({}), 'Supervisor');
    });
  });
}
