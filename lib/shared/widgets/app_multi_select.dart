import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

// ── AppMultiSelectItem ───────────────────────────────────────────────────────

class AppMultiSelectItem<T> {
  const AppMultiSelectItem({required this.value, required this.label});
  final T value;
  final String label;
}

// ── AppMultiSelect ───────────────────────────────────────────────────────────

class AppMultiSelect<T> extends StatefulWidget {
  const AppMultiSelect({
    super.key,
    required this.items,
    required this.selectedValues,
    required this.onChanged,
    this.placeholder = 'Selecciona...',
    this.searchable = false,
    this.maxOverlayHeight = 280.0,
    this.errorText,
  });

  final List<AppMultiSelectItem<T>> items;
  final List<T> selectedValues;
  final ValueChanged<List<T>> onChanged;
  final String placeholder;
  final bool searchable;
  final double maxOverlayHeight;
  final String? errorText;

  @override
  State<AppMultiSelect<T>> createState() => _AppMultiSelectState<T>();
}

class _AppMultiSelectState<T> extends State<AppMultiSelect<T>> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();
  final _triggerKey = GlobalKey();
  final _searchCtrl = TextEditingController();
  final _tapGroupId = Object();
  bool _open = false;
  List<AppMultiSelectItem<T>> _filtered = [];

  double _getTriggerWidth() {
    final box = _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size.width ?? 240;
  }

  @override
  void initState() {
    super.initState();
    _filtered = widget.items;
  }

  @override
  void didUpdateWidget(AppMultiSelect<T> old) {
    super.didUpdateWidget(old);
    if (old.selectedValues != widget.selectedValues) setState(() {});
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

  void _open_() {
    if (_open) return;
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

  void _toggle(AppMultiSelectItem<T> item) {
    final current = List<T>.from(widget.selectedValues);
    if (current.contains(item.value)) {
      current.remove(item.value);
    } else {
      current.add(item.value);
    }
    widget.onChanged(current);
  }

  void _remove(T value) {
    final current = List<T>.from(widget.selectedValues);
    current.remove(value);
    widget.onChanged(current);
  }

  void _onSearch(String query) {
    setState(() {
      _filtered = widget.items
          .where((i) => i.label.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  String _labelFor(T value) {
    return widget.items
            .where((i) => i.value == value)
            .firstOrNull
            ?.label ??
        value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
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
                onTap: _open_,
                child: Container(
                  key: _triggerKey,
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 40),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.ctSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: hasError
                          ? AppColors.ctDanger
                          : _open
                              ? AppColors.ctTeal
                              : AppColors.ctBorder2,
                      width: _open || hasError ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: widget.selectedValues.isEmpty
                            ? Text(
                                widget.placeholder,
                                style: AppTextStyles.body
                                    .copyWith(color: AppColors.ctText3),
                              )
                            : Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: widget.selectedValues.map((v) {
                                  return _Chip(
                                    label: _labelFor(v),
                                    onRemove: () => _remove(v),
                                  );
                                }).toList(),
                              ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: AppColors.ctText2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 4),
          Text(
            widget.errorText!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ctDanger),
          ),
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
                maxHeight: widget.maxOverlayHeight,
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
                            hintText: 'Buscar...',
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
                                  const EdgeInsets.symmetric(vertical: 4),
                              itemCount: _filtered.length,
                              itemBuilder: (_, i) {
                                final item = _filtered[i];
                                final checked = widget.selectedValues
                                    .contains(item.value);
                                return _CheckItem(
                                  label: item.label,
                                  checked: checked,
                                  onTap: () => _toggle(item),
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

// ── _Chip ────────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 8, right: 2, top: 2, bottom: 2),
      decoration: BoxDecoration(
        color: AppColors.ctTealLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ctTeal.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.ctTealDark,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: onRemove,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Icon(
                Icons.close_rounded,
                size: 13,
                color: AppColors.ctTealDark.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── _CheckItem ───────────────────────────────────────────────────────────────

class _CheckItem extends StatelessWidget {
  const _CheckItem({
    required this.label,
    required this.checked,
    required this.onTap,
  });
  final String label;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.ctSurface2,
        splashColor: AppColors.ctTealLight.withValues(alpha: 0.5),
        highlightColor: Colors.transparent,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: checked,
                  onChanged: (_) => onTap(),
                  activeColor: AppColors.ctTeal,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  side: BorderSide(
                    color: checked ? AppColors.ctTeal : AppColors.ctBorder2,
                    width: 1.5,
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.body.copyWith(
                    color: checked ? AppColors.ctText : AppColors.ctText2,
                    fontWeight:
                        checked ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
