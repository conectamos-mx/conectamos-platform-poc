import 'package:flutter/material.dart';
import 'colors.dart';

abstract final class AppTextStyles {
  // ── Títulos de página / screen title ─────────────────────────────────────
  // Onest 700 · 15px · −0.02em (DS: Screen title)
  static const TextStyle pageTitle = TextStyle(
    fontFamily: 'Onest',
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.ctText,
    letterSpacing: -0.02,
  );

  // Geist 400 · 13px · −0.01em
  static const TextStyle pageSubtitle = TextStyle(
    fontFamily: 'Geist',
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.ctText2,
    letterSpacing: -0.01,
  );

  // ── Títulos de sección / card ─────────────────────────────────────────────
  // Onest 600 · 13px · −0.02em (DS: Section heading)
  static const TextStyle cardTitle = TextStyle(
    fontFamily: 'Onest',
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.ctText,
    letterSpacing: -0.02,
  );

  // ── Topbar ────────────────────────────────────────────────────────────────
  // Onest 700 · 15px · −0.02em
  static const TextStyle topbarTitle = TextStyle(
    fontFamily: 'Onest',
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.ctText,
    letterSpacing: -0.02,
  );

  // Geist 400 · 11px
  static const TextStyle topbarSubtitle = TextStyle(
    fontFamily: 'Geist',
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: AppColors.ctText2,
    letterSpacing: -0.01,
  );

  // ── Sidebar ───────────────────────────────────────────────────────────────
  // Geist 400 · 12px · −0.01em
  static const TextStyle navItem = TextStyle(
    fontFamily: 'Geist',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.ctText2,
    letterSpacing: -0.01,
  );

  // Geist 600 · 12px · −0.01em
  static const TextStyle navItemActive = TextStyle(
    fontFamily: 'Geist',
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.ctTeal,
    letterSpacing: -0.01,
  );

  // Geist 700 · 9px · +0.08em · uppercase (DS: Eyebrow / section label)
  static const TextStyle navSectionLabel = TextStyle(
    fontFamily: 'Geist',
    fontSize: 9,
    fontWeight: FontWeight.w700,
    color: AppColors.ctText3,
    letterSpacing: 0.08,
  );

  // ── Formularios ───────────────────────────────────────────────────────────
  // Geist 600 · 12px · −0.01em (DS: Label / metadata)
  static const TextStyle formLabel = TextStyle(
    fontFamily: 'Geist',
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.ctText,
    letterSpacing: -0.01,
  );

  // ── Cuerpo / datos ────────────────────────────────────────────────────────
  // Geist 400 · 13px · −0.01em (DS: Body / chat message)
  static const TextStyle body = TextStyle(
    fontFamily: 'Geist',
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.ctText,
    letterSpacing: -0.01,
  );

  // Geist 400 · 11px
  static const TextStyle bodySmall = TextStyle(
    fontFamily: 'Geist',
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: AppColors.ctText2,
    letterSpacing: -0.01,
  );

  // Geist 400 · 10px (DS: Timestamp / caption)
  static const TextStyle caption = TextStyle(
    fontFamily: 'Geist',
    fontSize: 10,
    fontWeight: FontWeight.w400,
    color: AppColors.ctText3,
  );

  // ── Badges / tags ─────────────────────────────────────────────────────────
  // Geist 600 · 11px · −0.01em
  static const TextStyle badge = TextStyle(
    fontFamily: 'Geist',
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.01,
  );

  // ── Chips / filter labels ─────────────────────────────────────────────────
  // Geist 500 · 12px · −0.01em (DS: Chip label)
  static const TextStyle chipLabel = TextStyle(
    fontFamily: 'Geist',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.01,
  );

  // ── Tenant / chips ────────────────────────────────────────────────────────
  static const TextStyle tenantLabel = TextStyle(
    fontFamily: 'Geist',
    fontSize: 10,
    fontWeight: FontWeight.w500,
    color: AppColors.ctText3,
    letterSpacing: -0.01,
  );

  static const TextStyle tenantName = TextStyle(
    fontFamily: 'Geist',
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.ctText,
    letterSpacing: -0.01,
  );

  // ── Botones ───────────────────────────────────────────────────────────────
  // Geist 700 · 13px · −0.01em (DS: Button / primary action)
  static const TextStyle btnPrimary = TextStyle(
    fontFamily: 'Geist',
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.01,
  );

  // Geist 500 · 13px · −0.01em
  static const TextStyle btnSecondary = TextStyle(
    fontFamily: 'Geist',
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.ctText,
    letterSpacing: -0.01,
  );

  // ── KPI values ────────────────────────────────────────────────────────────
  // Onest 700 · 28px · −0.03em (DS: KPI value)
  static const TextStyle kpiValue = TextStyle(
    fontFamily: 'Onest',
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.ctText,
    letterSpacing: -0.03,
  );

  // Geist 600 · 10px · +0.07em · uppercase (DS: KPI label)
  static const TextStyle kpiLabel = TextStyle(
    fontFamily: 'Geist',
    fontSize: 10,
    fontWeight: FontWeight.w600,
    color: AppColors.ctText2,
    letterSpacing: 0.07,
  );
}
