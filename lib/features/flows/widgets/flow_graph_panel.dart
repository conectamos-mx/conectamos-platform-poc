import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';

import '../../../core/theme/app_theme.dart';

class FlowGraphPanel extends StatefulWidget {
  const FlowGraphPanel({super.key, required this.fields});

  final List<Map<String, dynamic>> fields;

  @override
  State<FlowGraphPanel> createState() => _FlowGraphPanelState();
}

class _FlowGraphPanelState extends State<FlowGraphPanel> {
  late Graph _graph;
  late SugiyamaAlgorithm _algorithm;

  @override
  void initState() {
    super.initState();
    _initAlgorithm();
    _buildGraph();
  }

  @override
  void didUpdateWidget(FlowGraphPanel old) {
    super.didUpdateWidget(old);
    if (old.fields != widget.fields) {
      _buildGraph();
    }
  }

  void _initAlgorithm() {
    final config = SugiyamaConfiguration()
      ..nodeSeparation = 24
      ..levelSeparation = 48
      ..orientation = SugiyamaConfiguration.ORIENTATION_TOP_BOTTOM;
    _algorithm = SugiyamaAlgorithm(config);
  }

  void _buildGraph() {
    final graph = Graph()..isTree = false;
    final nodeMap = <String, Node>{};

    for (final field in widget.fields) {
      final key = field['key'] as String? ?? '';
      if (key.isEmpty) continue;
      final node = Node.Id(key);
      nodeMap[key] = node;
      graph.addNode(node);
    }

    for (final field in widget.fields) {
      final key = field['key'] as String? ?? '';
      final showIf = field['show_if'];
      if (showIf == null) continue;
      final sourceKey = (showIf is Map) ? showIf['field'] as String? : null;
      if (sourceKey == null) continue;
      final source = nodeMap[sourceKey];
      final target = nodeMap[key];
      if (source == null || target == null) continue;
      graph.addEdge(source, target,
          paint: Paint()
            ..color = AppColors.ctTeal.withValues(alpha: 0.7)
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke);
    }

    setState(() => _graph = graph);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fields.isEmpty) {
      return const Center(
        child: Text(
          'Este flow no tiene campos definidos.',
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 13,
            color: AppColors.ctText3,
          ),
        ),
      );
    }

    final fieldsByKey = {
      for (final f in widget.fields)
        if ((f['key'] as String? ?? '').isNotEmpty) f['key'] as String: f,
    };

    return InteractiveViewer(
      constrained: false,
      boundaryMargin: const EdgeInsets.all(64),
      minScale: 0.5,
      maxScale: 2.0,
      child: GraphView(
        graph: _graph,
        algorithm: _algorithm,
        paint: Paint()
          ..color = AppColors.ctBorder2
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
        builder: (Node node) {
          final key = node.key?.value as String? ?? '';
          final field = fieldsByKey[key];
          return _FieldNode(
            label: field?['label'] as String? ?? key,
            type: field?['type'] as String? ?? 'text',
            hasShowIf: field?['show_if'] != null,
          );
        },
      ),
    );
  }
}

// ── _FieldNode ────────────────────────────────────────────────────────────────

const _kTypeLabels = <String, String>{
  'text':      'texto',
  'number':    'número',
  'date':      'fecha',
  'boolean':   'sí/no',
  'select':    'selección',
  'photo':     'foto',
  'location':  'ubicación',
  'asset_ref': 'catálogo',
};

class _FieldNode extends StatelessWidget {
  const _FieldNode({
    required this.label,
    required this.type,
    required this.hasShowIf,
  });

  final String label;
  final String type;
  final bool hasShowIf;

  @override
  Widget build(BuildContext context) {
    final isAssetRef = type == 'asset_ref';
    final borderColor = isAssetRef ? AppColors.ctTeal : AppColors.ctBorder2;
    final typeLabel = _kTypeLabels[type] ?? type;

    return SizedBox(
      width: 120,
      height: 60,
      child: Stack(
        children: [
          Container(
            width: 120,
            height: 60,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            decoration: BoxDecoration(
              color: AppColors.ctSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ctText,
                    height: 1.2,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isAssetRef
                        ? AppColors.ctTeal.withValues(alpha: 0.12)
                        : AppColors.ctSurface2,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    typeLabel,
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: isAssetRef ? AppColors.ctTealText : AppColors.ctText3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (hasShowIf)
            const Positioned(
              top: 4,
              right: 4,
              child: Icon(
                Icons.account_tree_outlined,
                size: 10,
                color: AppColors.ctText3,
              ),
            ),
        ],
      ),
    );
  }
}
