import 'package:flutter/material.dart';

abstract final class AppColors {
  // Teal — color de marca, solo para acentos
  static const ctTeal      = Color(0xFF59E0CC);
  static const ctTealHover = Color(0xFF66E2D0);
  static const ctTealDark  = Color(0xFF3ABFAD);
  static const ctTealLight = Color(0xFFCCFBF1);
  static const ctTealText  = Color(0xFF0F766E);

  // Navy / Ink
  static const ctNavy      = Color(0xFF0B132B);
  static const ctSidebarBg = Color(0xFF0E1829);
  static const ctInk800    = Color(0xFF1C2541);
  static const ctInk700    = Color(0xFF3A506B);

  // Texto
  static const ctText  = Color(0xFF111827);
  static const ctText2 = Color(0xFF6B7280);
  static const ctText3 = Color(0xFF9CA3AF);

  // Superficies
  static const ctBg       = Color(0xFFF9FAFB);
  static const ctSurface  = Color(0xFFFFFFFF);
  static const ctSurface2 = Color(0xFFF3F4F6);

  // Bordes
  static const ctBorder  = Color(0xFFE5E7EB);
  static const ctBorder2 = Color(0xFFD1D5DB);

  // Semánticos
  static const ctOk     = Color(0xFF10B981);
  static const ctOkBg   = Color(0xFFD1FAE5);
  static const ctOkText = Color(0xFF065F46);

  static const ctWarn     = Color(0xFFF59E0B);
  static const ctWarnBg   = Color(0xFFFEF3C7);
  static const ctWarnText = Color(0xFF92400E);

  static const ctDanger  = Color(0xFFEF4444);
  static const ctRedBg   = Color(0xFFFEE2E2);
  static const ctRedText = Color(0xFF991B1B);

  static const ctInfo     = Color(0xFF3B82F6);
  static const ctInfoBg   = Color(0xFFDBEAFE);
  static const ctInfoText = Color(0xFF1E40AF);

  // Naranja — escalaciones reabiertas
  static const ctOrangeBg   = Color(0xFFFFEDD5);
  static const ctOrangeText = Color(0xFF9A3412);

  // Púrpura — tipo fecha en badges de campo
  static const ctPurpleBg   = Color(0xFFEDE9FE);
  static const ctPurpleText = Color(0xFF5B21B6);

  // Canales externos
  static const ctWa       = Color(0xFF25D366);
  static const ctWaBubble = Color(0xFFDCF8C6);
  static const ctTg       = Color(0xFF229ED9);
  static const ctTgBubble = Color(0xFFDBEAFE);

  // Mensajes / snackbar
  static const waMessageBubble = Color(0xFFE7FFDB);
  static const errorBorder     = Color(0xFFFCA5A5);
  static const snackbarSuccess = Color(0xFF059669);

  // Alias legacy — no eliminar hasta migrar referencias
  static const waBubbleAi = ctWaBubble;
}
