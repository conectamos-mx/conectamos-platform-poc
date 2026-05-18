import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_button.dart';

// ── Pantalla ──────────────────────────────────────────────────────────────────

class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key, required this.operatorName});
  final String operatorName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _ActionBar(operatorName: operatorName),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: _SessionBody(operatorName: operatorName),
          ),
        ),
      ],
    );
  }
}

// ── Action bar ────────────────────────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.operatorName});
  final String operatorName;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.ctSurface,
        border: Border(bottom: BorderSide(color: AppColors.ctBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Sesión · $operatorName',
                  style: AppTextStyles.body.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 1),
                Text(
                  'Hoy · Turno iniciado 07:03 · En curso',
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
          AppButton(
            label: '← Vista general',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: () => context.go('/'),
          ),
          const SizedBox(width: 8),
          AppButton(
            label: 'Ver conversación',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: () => context.go('/conversaciones'),
          ),
        ],
      ),
    );
  }
}

// ── Cuerpo de la sesión ───────────────────────────────────────────────────────

class _SessionBody extends StatelessWidget {
  const _SessionBody({required this.operatorName});
  final String operatorName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // KPIs
        _KpiRow(),
        const SizedBox(height: 20),

        // Dos columnas: timeline + paneles de flujo
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Expanded(child: _Timeline()),
            SizedBox(width: 16),
            SizedBox(width: 220, child: _FlowPanels()),
          ],
        ),
      ],
    );
  }
}

// ── Fila de KPIs ─────────────────────────────────────────────────────────────

class _KpiRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SessionKpiCard(
            topBorderColor: AppColors.ctOk,
            label: 'CHECKLIST DE INICIO',
            valueWidget: const Icon(
              Icons.check_circle_rounded,
              size: 32,
              color: AppColors.ctOk,
            ),
            subtext: 'Completado · 07:03',
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: _SessionKpiCard(
            topBorderColor: AppColors.ctTeal,
            label: 'IDs GENERADOS',
            valueWidget: _KpiValueText('3'),
            subtext: 'En esta sesión',
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: _SessionKpiCard(
            topBorderColor: AppColors.ctBorder2,
            label: 'ALERTAS ABIERTAS',
            valueWidget: _KpiValueText('0'),
            subtext: 'Sin incidencias',
          ),
        ),
      ],
    );
  }
}

class _KpiValueText extends StatelessWidget {
  const _KpiValueText(this.value);
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: AppTextStyles.kpiValue.copyWith(height: 1),
    );
  }
}

class _SessionKpiCard extends StatelessWidget {
  const _SessionKpiCard({
    required this.topBorderColor,
    required this.label,
    required this.valueWidget,
    required this.subtext,
  });

  final Color topBorderColor;
  final String label;
  final Widget valueWidget;
  final String subtext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: topBorderColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: AppTextStyles.kpiLabel.copyWith(letterSpacing: 0.6),
          ),
          const SizedBox(height: 8),
          valueWidget,
          const SizedBox(height: 5),
          Text(
            subtext,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctText3),
          ),
        ],
      ),
    );
  }
}

// ── Timeline ──────────────────────────────────────────────────────────────────

class _TimelineEvent {
  const _TimelineEvent({
    required this.dotColor,
    required this.title,
    required this.detail,
    required this.time,
    this.faded = false,
  });
  final Color dotColor;
  final String title;
  final String detail;
  final String time;
  final bool faded;
}

const _kTimelineEvents = [
  _TimelineEvent(
    dotColor: AppColors.ctOk,
    title: 'Inicio de turno ✓',
    detail: 'Checklist completado · llegó al punto de origen',
    time: '07:03',
  ),
  _TimelineEvent(
    dotColor: AppColors.ctTeal,
    title: 'ID-001 generado · Flujo 2',
    detail: '3 unidades en tránsito al primer punto',
    time: '07:45',
  ),
  _TimelineEvent(
    dotColor: AppColors.ctOk,
    title: 'ID-001 cerrado · Entrega exitosa',
    detail: 'Confirmó entrega · evidencia recibida',
    time: '09:12',
  ),
  _TimelineEvent(
    dotColor: AppColors.ctTeal,
    title: 'ID-002 generado · Flujo 2',
    detail: '3 unidades · segundo punto',
    time: '09:42',
  ),
  _TimelineEvent(
    dotColor: AppColors.ctBorder2,
    title: 'Esperando siguiente evento...',
    detail: '',
    time: 'Ahora',
    faded: true,
  ),
];

class _Timeline extends StatelessWidget {
  const _Timeline();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: ClipRect(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LÍNEA DE TIEMPO',
            style: AppTextStyles.kpiLabel.copyWith(color: AppColors.ctText3, letterSpacing: 1.2),
          ),
          const SizedBox(height: 16),
          ..._kTimelineEvents.asMap().entries.map((entry) {
            final i = entry.key;
            final event = entry.value;
            final isLast = i == _kTimelineEvents.length - 1;
            return _TimelineItem(
              event: event,
              isLast: isLast,
            );
          }),
        ],
        ),  // Column
      ),    // ClipRect
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.event, required this.isLast});
  final _TimelineEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dot + line column
          SizedBox(
            width: 20,
            child: Column(
              children: [
                const SizedBox(height: 3),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: event.dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: AppColors.ctBorder,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.title,
                          style: AppTextStyles.formLabel.copyWith(
                            color: event.faded ? AppColors.ctText3 : AppColors.ctText,
                          ),
                        ),
                      ),
                      Text(
                        event.time,
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                  if (event.detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      event.detail,
                      style: AppTextStyles.bodySmall.copyWith(height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Paneles de flujo (columna derecha) ────────────────────────────────────────

class _FlowPanels extends StatelessWidget {
  const _FlowPanels();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'IDs POR FLUJO',
          style: AppTextStyles.kpiLabel.copyWith(color: AppColors.ctText3, letterSpacing: 1.2),
        ),
        SizedBox(height: 10),
        _FlowPanel(
          title: 'Flujo 1 · Turno',
          child: _FlowTurnoContent(),
        ),
        SizedBox(height: 10),
        _FlowPanel(
          title: 'Flujo 2 · Registros',
          child: _FlowRegistrosContent(),
        ),
        SizedBox(height: 10),
        _FlowPanel(
          title: 'Flujo 3 · Incidencias',
          child: _FlowIncidenciasContent(),
        ),
      ],
    );
  }
}

class _FlowPanel extends StatelessWidget {
  const _FlowPanel({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.ctSurface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.ctBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: AppColors.ctText),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

// ── Contenido: Flujo 1 ────────────────────────────────────────────────────────

class _FlowTurnoContent extends StatelessWidget {
  const _FlowTurnoContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_rounded, size: 13, color: AppColors.ctOk),
            const SizedBox(width: 5),
            Text(
              'Inicio: ✓ 07:03',
              style: AppTextStyles.bodySmall.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.ctOk),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(Icons.schedule_rounded, size: 13, color: AppColors.ctText3),
            const SizedBox(width: 5),
            Text(
              'Cierre: Pendiente',
              style: AppTextStyles.bodySmall.copyWith(fontSize: 12, color: AppColors.ctText3),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Contenido: Flujo 2 ────────────────────────────────────────────────────────

class _IdEntry {
  const _IdEntry({
    required this.id,
    required this.statusLabel,
    required this.statusBg,
    required this.statusTextColor,
  });
  final String id;
  final String statusLabel;
  final Color statusBg;
  final Color statusTextColor;
}

const _kIds = [
  _IdEntry(
    id: 'ID-001',
    statusLabel: 'Cerrado',
    statusBg: AppColors.ctOkBg,
    statusTextColor: AppColors.ctOkText,
  ),
  _IdEntry(
    id: 'ID-002',
    statusLabel: 'Abierto',
    statusBg: AppColors.ctTealLight,
    statusTextColor: AppColors.ctTealDark,
  ),
  _IdEntry(
    id: 'ID-003',
    statusLabel: 'Abierto',
    statusBg: AppColors.ctTealLight,
    statusTextColor: AppColors.ctTealDark,
  ),
];

class _FlowRegistrosContent extends StatelessWidget {
  const _FlowRegistrosContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Contador + badge
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '3',
              style: AppTextStyles.kpiValue.copyWith(fontSize: 22, height: 1),
            ),
            const SizedBox(width: 6),
            Text(
              'IDs generados',
              style: AppTextStyles.bodySmall,
            ),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.ctOkBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '2 cerrados',
                style: AppTextStyles.kpiLabel.copyWith(color: AppColors.ctOkText),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Lista de IDs
        ..._kIds.map((entry) => _IdRow(entry: entry)),
      ],
    );
  }
}

class _IdRow extends StatefulWidget {
  const _IdRow({required this.entry});
  final _IdEntry entry;

  @override
  State<_IdRow> createState() => _IdRowState();
}

class _IdRowState extends State<_IdRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {},
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          margin: const EdgeInsets.only(bottom: 4),
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color:
                _hovered ? AppColors.ctSurface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.tag_rounded,
                size: 12,
                color: AppColors.ctText3,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  widget.entry.id,
                  style: AppTextStyles.bodySmall.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.ctText),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: widget.entry.statusBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  widget.entry.statusLabel,
                  style: AppTextStyles.kpiLabel.copyWith(color: widget.entry.statusTextColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Contenido: Flujo 3 ────────────────────────────────────────────────────────

class _FlowIncidenciasContent extends StatelessWidget {
  const _FlowIncidenciasContent();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.check_circle_outline_rounded,
            size: 14, color: AppColors.ctOk),
        const SizedBox(width: 6),
        Text(
          'Sin incidencias ✓',
          style: AppTextStyles.bodySmall.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.ctOk),
        ),
      ],
    );
  }
}
