/// Ventana de 24h de WhatsApp (regla de Meta).
///
/// Tras el ultimo inbound del operador, Meta permite texto libre durante 24h.
/// Normaliza SIEMPRE a UTC en ambos lados (ADR-414).
library;

const _whatsAppWindow = Duration(hours: 24);

/// [lastInboundAtIso]: ISO-8601 del ultimo mensaje inbound del operador.
/// null / invalido -> false (sin inbound = ventana cerrada).
/// Boundary: exactamente 24h = cerrada (difference < window, no <=).
bool whatsAppWindowOpen(String? lastInboundAtIso) {
  if (lastInboundAtIso == null) return false;
  final dt = DateTime.tryParse(lastInboundAtIso);
  if (dt == null) return false;
  return DateTime.now().toUtc().difference(dt.toUtc()) < _whatsAppWindow;
}
