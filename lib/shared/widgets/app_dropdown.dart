import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

// ── AppDropdownItem ──────────────────────────────────────────────────────────

class AppDropdownItem<T> {
  const AppDropdownItem({
    required this.value,
    required this.label,
    this.icon,
    this.subtitle,
    this.enabled = true,
  });

  final T value;
  final String label;
  final IconData? icon;
  final String? subtitle;
  final bool enabled;
}

// ── AppDropdown ──────────────────────────────────────────────────────────────

class AppDropdown<T> extends StatefulWidget {
  const AppDropdown({
    super.key,
    required this.items,
    required this.onChanged,
    this.value,
    this.hint = 'Seleccionar',
    this.label,
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.searchable = false,
    this.searchHint = 'Buscar...',
    this.maxOverlayHeight = 280.0,
  });

  final List<AppDropdownItem<T>> items;
  final ValueChanged<T?> onChanged;
  final T? value;
  final String hint;
  final String? label;
  final String? helperText;
  final String? errorText;
  final bool enabled;
  final bool searchable;
  final String searchHint;
  final double maxOverlayHeight;

  @override
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends State<AppDropdown<T>> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();
  final _triggerKey = GlobalKey();
  final _searchCtrl = TextEditingController();
  final _tapGroupId = Object();
  bool _open = false;
  List<AppDropdownItem<T>> _filtered = [];

  double _getTriggerWidth() {
    final box = _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size.width ?? 240;
  }

  double _getAvailableHeight() {
    final box = _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || _triggerKey.currentContext == null) {
      return widget.maxOverlayHeight;
    }
    final triggerBottomY =
        box.localToGlobal(Offset(0, box.size.height)).dy;
    final viewportHeight =
        MediaQuery.of(_triggerKey.currentContext!).size.height;
    final available = viewportHeight - triggerBottomY - 16;
    return available.clamp(120.0, widget.maxOverlayHeight);
  }

  @override
  void initState() {
    super.initState();
    _filtered = widget.items;
  }

  @override
  void didUpdateWidget(AppDropdown<T> old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) setState(() {});
    if (old.items != widget.items) {
      setState(() {
        _filtered = widget.items
            .where((i) => i.label
                .toLowerCase()
                .contains(_searchCtrl.text.toLowerCase()))
            .toList();
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  AppDropdownItem<T>? get _selected =>
      widget.items.where((i) => i.value == widget.value).firstOrNull;

  bool get _hasError => widget.errorText != null;

  void _open_() {
    if (!widget.enabled || _open) return;
    _searchCtrl.clear();
    _filtered = widget.items;
    setState(() => _open = true);
    _controller.show();
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
    _controller.hide();
  }

  void _toggle() {
    if (_open) {
      _close();
    } else {
      _open_();
    }
  }

  void _select(AppDropdownItem<T> item) {
    if (!item.enabled) return;
    final value = item.value;
    _close();
    widget.onChanged(value);
  }

  void _onSearch(String query) {
    setState(() {
      _filtered = widget.items
          .where((i) => i.label.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!, style: AppTextStyles.formLabel),
          const SizedBox(height: 6),
        ],
        CompositedTransformTarget(
          link: _link,
          child: OverlayPortal(
            controller: _controller,
            overlayChildBuilder: (_) => _buildOverlay(),
            child: TapRegion(
              groupId: _tapGroupId,
              onTapOutside: (_) => _close(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggle,
                child: AnimatedContainer(
                  key: _triggerKey,
                  duration: const Duration(milliseconds: 150),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: widget.enabled
                        ? AppColors.ctSurface
                        : AppColors.ctSurface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _hasError
                          ? AppColors.ctDanger
                          : _open
                              ? AppColors.ctTeal
                              : AppColors.ctBorder2,
                      width: _open ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      if (_selected?.icon != null) ...[
                        Icon(_selected!.icon,
                            size: 16, color: AppColors.ctText2),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          _selected?.label ?? widget.hint,
                          style: AppTextStyles.body.copyWith(
                            color: _selected != null
                                ? (widget.enabled
                                    ? AppColors.ctText
                                    : AppColors.ctText3)
                                : AppColors.ctText3,
                          ),
                          softWrap: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: widget.enabled
                              ? AppColors.ctText2
                              : AppColors.ctText3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_hasError) ...[
          const SizedBox(height: 3),
          Text(widget.errorText!,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.ctDanger)),
        ] else if (widget.helperText != null) ...[
          const SizedBox(height: 3),
          Text(widget.helperText!,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.ctText3)),
        ],
      ],
    );
  }

  Widget _buildOverlay() {
    return CompositedTransformFollower(
      link: _link,
      showWhenUnlinked: false,
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      offset: const Offset(0, 4),
      child: Align(
        alignment: Alignment.topLeft,
        child: TapRegion(
          groupId: _tapGroupId,
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: _getAvailableHeight(),
                minWidth: _getTriggerWidth(),
                maxWidth: _getTriggerWidth(),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.ctSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.ctBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.searchable) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                        child: TextField(
                          controller: _searchCtrl,
                          autofocus: true,
                          style: AppTextStyles.body,
                          decoration: InputDecoration(
                            hintText: widget.searchHint,
                            hintStyle: AppTextStyles.body
                                .copyWith(color: AppColors.ctText3),
                            prefixIcon: const Icon(Icons.search_rounded,
                                size: 16, color: AppColors.ctText3),
                            filled: true,
                            fillColor: AppColors.ctSurface2,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide:
                                  const BorderSide(color: AppColors.ctBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide:
                                  const BorderSide(color: AppColors.ctBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(
                                  color: AppColors.ctTeal, width: 1.5),
                            ),
                          ),
                          onChanged: _onSearch,
                        ),
                      ),
                      const Divider(height: 1, color: AppColors.ctBorder),
                    ],
                    Flexible(
                      child: _filtered.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text('Sin resultados',
                                  style: AppTextStyles.body
                                      .copyWith(color: AppColors.ctText3)),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 6),
                              itemCount: _filtered.length,
                              itemBuilder: (_, i) {
                                final item = _filtered[i];
                                return _DropdownItemTile(
                                  item: item,
                                  isSelected: item.value == widget.value,
                                  onTap: () => _select(item),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── _DropdownItemTile ────────────────────────────────────────────────────────

class _DropdownItemTile<T> extends StatelessWidget {
  const _DropdownItemTile({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final AppDropdownItem<T> item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: item.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: item.enabled ? onTap : null,
          borderRadius: BorderRadius.circular(6),
          hoverColor: AppColors.ctSurface2,
          splashColor: AppColors.ctTealLight.withValues(alpha: 0.5),
          highlightColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.ctTealLight : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            margin: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                if (item.icon != null) ...[
                  Icon(
                    item.icon,
                    size: 15,
                    color: isSelected
                        ? AppColors.ctTealDark
                        : item.enabled
                            ? AppColors.ctText2
                            : AppColors.ctText3,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: AppTextStyles.body.copyWith(
                          color: isSelected
                              ? AppColors.ctTealDark
                              : item.enabled
                                  ? AppColors.ctText
                                  : AppColors.ctText3,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      if (item.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.subtitle!,
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.ctText3),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check_rounded,
                      size: 14, color: AppColors.ctTealDark),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
