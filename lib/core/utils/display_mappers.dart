import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../../shared/widgets/app_badge.dart';

// ---------------------------------------------------------------------------
// Display-mapper helpers — pure functions for UI label / color / icon mapping.
// Extracted from feature screens (PLA-69).
// ---------------------------------------------------------------------------

/// Returns up to two uppercase initials from [name].
/// For names with 3+ parts, uses the first and last part (e.g. "Ana Maria Lopez" -> "AL").
String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return '${parts[0][0]}${parts.last[0]}'.toUpperCase();
}

/// Parses a CSS hex color string (e.g. "#3ABFAD" or "3ABFAD") into a [Color].
/// Returns [AppColors.ctText3] on null, malformed, or non-6-digit input.
Color hexColor(String? hex) {
  try {
    final h = (hex ?? '#9CA3AF').replaceAll('#', '');
    if (h.length != 6) return AppColors.ctText3;
    return Color(int.parse('FF$h', radix: 16));
  } catch (_) {
    return AppColors.ctText3;
  }
}

/// Emoji-prefixed fallback label for a media message type.
String mediaFallback(String type) {
  switch (type) {
    case 'image':    return '[📷 Imagen]';
    case 'audio':    return '[🎤 Nota de voz]';
    case 'video':    return '[🎥 Video]';
    case 'document': return '[📄 Documento]';
    case 'sticker':  return '[😊 Sticker]';
    case 'location': return '[📍 Ubicación]';
    default:         return '[📎 Archivo]';
  }
}

/// Icon for a media message type.
IconData mediaIcon(String mediaType) {
  switch (mediaType) {
    case 'image':    return Icons.image_outlined;
    case 'video':    return Icons.videocam_outlined;
    case 'audio':    return Icons.mic_outlined;
    case 'document': return Icons.attach_file_rounded;
    default:         return Icons.attach_file_rounded;
  }
}

/// Human-readable label for a media message type.
String mediaLabel(String mediaType) {
  switch (mediaType) {
    case 'image':    return 'Imagen';
    case 'video':    return 'Video';
    case 'audio':    return 'Audio';
    case 'document': return 'Archivo';
    default:         return 'Adjunto';
  }
}

/// Badge info (label + variant) for operator active/inactive status.
({String label, AppBadgeVariant variant}) statusBadgeInfo(String? status) {
  switch (status) {
    case 'active':
      return (label: 'Activo', variant: AppBadgeVariant.ok);
    default:
      return (label: 'Inactivo', variant: AppBadgeVariant.neutral);
  }
}

/// Badge variant for Telegram link status.
AppBadgeVariant telegramBadgeVariant(String status) {
  switch (status) {
    case 'linked':
      return AppBadgeVariant.teal;
    case 'pending':
      return AppBadgeVariant.warn;
    default:
      return AppBadgeVariant.warn;
  }
}

/// Badge label for Telegram link status.
String telegramBadgeLabel(String status) {
  switch (status) {
    case 'linked':
      return 'Telegram vinculado';
    case 'pending':
      return 'Vinculacion pendiente';
    default:
      return 'Invitacion expirada';
  }
}

/// Extracts a displayable body from a message map.
/// Falls back to [mediaFallback] when raw_body is empty.
String msgBody(Map<String, dynamic> msg) {
  final raw = msg['raw_body'] as String?;
  if (raw != null && raw.isNotEmpty) return raw;
  return mediaFallback(msg['message_type'] as String? ?? '');
}

/// Resolves the display name for outbound messages.
String outboundSenderName(Map<String, dynamic> msg) {
  final fromName = msg['from_name'] as String?;
  if (fromName != null && fromName.isNotEmpty) return fromName;
  final origin = msg['origin'] as String?;
  if (origin == 'ai_worker') return 'AI Worker';
  final sentByUserId = msg['sent_by_user_id'] as String?;
  if (sentByUserId != null && sentByUserId.isNotEmpty) return 'Agente';
  return 'Supervisor';
}
