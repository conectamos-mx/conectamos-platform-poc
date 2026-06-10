import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';

/// Selector de items de un catálogo para campos asset_ref.
/// Llama GET /flows/catalog-items/{catalogSlug}?q={query}&limit=20
/// autenticado con el JWT del tenant (mismo Bearer que el resto de la app).
class AssetItemSelector extends ConsumerStatefulWidget {
  const AssetItemSelector({
    super.key,
    required this.catalogSlug,
    required this.onSelected,
    this.initialItemId,
    this.initialDisplayText,
  });

  final String catalogSlug;
  final void Function(Map<String, dynamic> item) onSelected;
  final String? initialItemId;
  final String? initialDisplayText;

  @override
  ConsumerState<AssetItemSelector> createState() => _AssetItemSelectorState();
}

class _AssetItemSelectorState extends ConsumerState<AssetItemSelector> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  bool _showList = false;
  Timer? _debounce;

  // Selected item state
  String? _selectedItemId;
  String? _selectedDisplayText;

  @override
  void initState() {
    super.initState();
    _selectedItemId = widget.initialItemId;
    _selectedDisplayText = widget.initialDisplayText;
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _fetch(_searchCtrl.text.trim());
    });
  }

  Future<void> _fetch(String q) async {
    setState(() {
      _loading = true;
      _showList = true;
    });
    try {
      final resp = await ref.read(apiClientProvider).dio.get(
        '/flows/catalog-items/${widget.catalogSlug}',
        queryParameters: {'q': q, 'limit': 20},
      );
      if (!mounted) return;
      final raw = resp.data;
      final list = raw is List ? raw : [];
      setState(() {
        _results = List<Map<String, dynamic>>.from(
            list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = [];
        _loading = false;
      });
    }
  }

  void _select(Map<String, dynamic> item) {
    setState(() {
      _selectedItemId = item['item_id'] as String?;
      _selectedDisplayText = item['display_text'] as String?;
      _showList = false;
      _results = [];
      _searchCtrl.clear();
    });
    widget.onSelected(item);
  }

  void _clear() {
    setState(() {
      _selectedItemId = null;
      _selectedDisplayText = null;
    });
    widget.onSelected({});
  }

  @override
  Widget build(BuildContext context) {
    // If item already selected, show chip + clear button
    if (_selectedItemId != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.ctTeal.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.ctTeal.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.inventory_2_outlined,
                size: 14, color: AppColors.ctTeal),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _selectedDisplayText ?? _selectedItemId!,
                style: AppTextStyles.bodySmall.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.ctText),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _clear,
              child: const Icon(Icons.close, size: 14, color: AppColors.ctText2),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search field
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.ctSurface2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.ctBorder2),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  style: AppTextStyles.body,
                  decoration: InputDecoration(
                    hintText: 'Buscar item del catálogo…',
                    hintStyle: AppTextStyles.body.copyWith(color: AppColors.ctText3),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  onTap: () {
                    if (_results.isEmpty && _searchCtrl.text.isEmpty) {
                      _fetch('');
                    }
                  },
                ),
              ),
              if (_loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppColors.ctTeal,
                  ),
                )
              else
                const Icon(Icons.search, size: 16, color: AppColors.ctText2),
            ],
          ),
        ),

        // Results dropdown
        if (_showList) ...[
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(
              color: AppColors.ctSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.ctBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _results.isEmpty && !_loading
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Text(
                      _searchCtrl.text.length > 2
                          ? 'Sin resultados'
                          : 'Escribe para buscar…',
                      style: AppTextStyles.bodySmall.copyWith(fontSize: 12, color: AppColors.ctText3),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _results.length,
                    itemBuilder: (_, i) {
                      final item = _results[i];
                      final displayText =
                          item['display_text'] as String? ?? '—';
                      return InkWell(
                        onTap: () => _select(item),
                        borderRadius: i == 0
                            ? const BorderRadius.vertical(
                                top: Radius.circular(8))
                            : i == _results.length - 1
                                ? const BorderRadius.vertical(
                                    bottom: Radius.circular(8))
                                : BorderRadius.zero,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 9),
                          child: Text(
                            displayText,
                            style: AppTextStyles.body,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }
}
