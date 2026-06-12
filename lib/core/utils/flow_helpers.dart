/// Returns true if [flow] is a query flow (has behavior.query_config).
/// Single source of truth for flow type detection per R1 (PLA-205).
bool isQueryFlow(Map<String, dynamic> flow) {
  final behavior = flow['behavior'];
  if (behavior is! Map) return false;
  return behavior['query_config'] != null;
}
