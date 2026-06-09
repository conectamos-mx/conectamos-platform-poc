/// Toggle de permisos con cascada de un solo nivel (PLA-70).
///
/// IMPORTANTE — profundidad de grafo = 1:
/// - Al ACTIVAR: activa el prerequisito DIRECTO (un nivel hacia arriba).
///   Si el prerequisito tiene a su vez un prerequisito, este NO se activa.
/// - Al DESACTIVAR: desactiva los dependientes DIRECTOS (un nivel hacia abajo).
///   Si un dependiente tiene a su vez dependientes, estos NO se desactivan.
///
/// Un prerequisito transitivo (A->B->C) NO cascadea correctamente:
/// desactivar A desactiva B pero deja C huerfano; activar C activa B
/// pero deja A inactivo. Este es el comportamiento documentado y
/// cubierto por golden tests. Ver PLA-70.
library;

typedef ToggleResult = ({
  Map<String, bool> grants,
  List<String> cascadeMessages,
});

/// Toglea un permiso y aplica cascada de un nivel.
///
/// [currentGrants]: mapa actual de permisos (key -> granted).
/// [module], [action]: identifican el permiso a togglear (key = '$module.$action').
/// [prerequisites]: mapa dependiente -> prerequisito (e.g. 'flows.manage' -> 'flows.view').
/// [labels]: mapa permKey -> label de UI para mensajes de cascada.
///
/// Retorna el nuevo estado de grants y los mensajes de cascada generados.
/// Funcion pura: mismas entradas -> mismas salidas, sin estado externo.
ToggleResult togglePermission({
  required Map<String, bool> currentGrants,
  required String module,
  required String action,
  required Map<String, String> prerequisites,
  required Map<String, String> labels,
}) {
  final key = '$module.$action';
  final current = currentGrants[key] ?? false;
  final newGrants = Map<String, bool>.from(currentGrants);
  final cascades = <String>[];

  if (!current) {
    // Activating: also activate prerequisite if needed (one level up)
    newGrants[key] = true;
    final prereq = prerequisites[key];
    if (prereq != null && !(newGrants[prereq] ?? false)) {
      newGrants[prereq] = true;
      cascades.add(
        'Se activó también "${labels[prereq] ?? prereq}" '
        'porque es requerido por "${labels[key] ?? key}".',
      );
    }
  } else {
    // Deactivating: also deactivate dependents (one level down)
    newGrants[key] = false;
    for (final entry in prerequisites.entries) {
      if (entry.value == key && (newGrants[entry.key] ?? false)) {
        newGrants[entry.key] = false;
        cascades.add(
          'Se desactivó también "${labels[entry.key] ?? entry.key}" '
          'porque requiere "${labels[key] ?? key}".',
        );
      }
    }
  }

  return (grants: newGrants, cascadeMessages: cascades);
}
