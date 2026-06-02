import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Uploads an image to Supabase Storage and returns the public URL.
///
/// Used by avatar tap action and custom field file/photo inputs.
/// Throws with a user-facing message on failure.
Future<String> uploadOperatorImage({
  required String operatorId,
  required Uint8List bytes,
  required String extension,
  String? subfolder,
}) async {
  final folder = operatorId.isNotEmpty ? operatorId : _generateUuid();
  final ts = DateTime.now().millisecondsSinceEpoch;
  final ext = extension.toLowerCase();
  final sub = subfolder != null ? '$subfolder/' : '';
  final path = 'operators/$folder/$sub$ts.$ext';
  final contentType = ext == 'png' ? 'image/png' : 'image/jpeg';

  await Supabase.instance.client.storage
      .from('wa-media')
      .uploadBinary(path, bytes,
          fileOptions: FileOptions(contentType: contentType));

  return Supabase.instance.client.storage
      .from('wa-media')
      .getPublicUrl(path);
}

/// Uploads any file (non-image) and returns the public URL.
Future<String> uploadOperatorFile({
  required String operatorId,
  required Uint8List bytes,
  required String extension,
  String? subfolder,
}) async {
  final folder = operatorId.isNotEmpty ? operatorId : _generateUuid();
  final ts = DateTime.now().millisecondsSinceEpoch;
  final ext = extension.toLowerCase();
  final sub = subfolder != null ? '$subfolder/' : '';
  final path = 'operators/$folder/$sub$ts.$ext';

  await Supabase.instance.client.storage
      .from('wa-media')
      .uploadBinary(path, bytes,
          fileOptions:
              const FileOptions(contentType: 'application/octet-stream'));

  return Supabase.instance.client.storage
      .from('wa-media')
      .getPublicUrl(path);
}

String _generateUuid() {
  final rng = Random.secure();
  final b = List.generate(16, (_) => rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
      '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
