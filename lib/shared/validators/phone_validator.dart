/// E.164 phone validator shared across the platform.
///
/// Returns `null` when [value] is valid or empty/null (caller decides if
/// the field is required). Returns a user-facing error string otherwise.
///
/// Validation rules (matches ITU-T E.164):
///   - Must start with `+`
///   - Digits after `+` must be 10–15
String? validatePhoneE164(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final cleaned = value.replaceAll(RegExp(r'[\s\-\(\)]'), '');
  if (!cleaned.startsWith('+')) {
    return 'Debe iniciar con + (ej. +52 55 1234 5678)';
  }
  final digits = cleaned.substring(1);
  if (digits.length < 10 ||
      digits.length > 15 ||
      !RegExp(r'^\d+$').hasMatch(digits)) {
    return 'Formato inválido. Usa formato E.164 (ej. +52 55 1234 5678)';
  }
  return null;
}
