// Reusable catalog fixtures for integration tests (T4).
//
// Every fixture includes both `id` (used for Keys and mock paths)
// and `slug` (used for navigation assertions).

const kCatalog1 = <String, dynamic>{
  'id': 'cat-001',
  'slug': 'productos',
  'label': 'Productos',
  'name': 'Productos',
  'source_type': 'manual',
  'item_count': 12,
  'last_synced_at': null,
  'sync_status': 'manual',
};

const kCatalog2 = <String, dynamic>{
  'id': 'cat-002',
  'slug': 'sucursales',
  'label': 'Sucursales',
  'name': 'Sucursales',
  'source_type': 'google_sheets',
  'item_count': 5,
  'last_synced_at': '2026-06-01T10:00:00Z',
  'sync_status': 'synced',
};

const kCatalogList = <Map<String, dynamic>>[kCatalog1, kCatalog2];

const kCatalogItems = <Map<String, dynamic>>[
  {
    'id': 'item-001',
    'data': {'sku': 'A100', 'nombre': 'Widget A', 'precio': 99.5},
  },
  {
    'id': 'item-002',
    'data': {'sku': 'B200', 'nombre': 'Widget B', 'precio': 149.0},
  },
];

const kCatalogSyncLog = <Map<String, dynamic>>[
  {
    'id': 'log-001',
    'status': 'success',
    'rows_synced': 12,
    'started_at': '2026-06-01T10:00:00Z',
    'finished_at': '2026-06-01T10:00:03Z',
  },
];

const kCatalogUsages = <Map<String, dynamic>>[
  {
    'flow_slug': 'ventas',
    'flow_label': 'Flujo de ventas',
    'field_label': 'producto_id',
  },
];

// ── Wizard fixtures (T4b) ───────────────────────────────────────────────────

const kFieldTypes = <Map<String, dynamic>>[
  {'key': 'text', 'label': 'Texto', 'description': 'Campo de texto libre'},
  {'key': 'number', 'label': 'Número', 'description': 'Valor numérico'},
  {'key': 'boolean', 'label': 'Booleano', 'description': 'Verdadero/falso'},
  {'key': 'date', 'label': 'Fecha', 'description': 'Fecha sin hora'},
];

const kGoogleConnected = <String, dynamic>{
  'connected': true,
  'email': 'test@example.com',
  'connected_at': '2026-05-01T08:00:00Z',
};

const kMicrosoftConnected = <String, dynamic>{
  'connections': [
    {'provider': 'microsoft', 'status': 'active'},
  ],
};

// Response from POST /api/v1/catalogs after wizard submit
const kCreatedCatalog = <String, dynamic>{
  'id': 'cat-new-001',
  'slug': 'productos',
  'label': 'Productos',
  'source_type': 'manual',
};

// ── Detail + CRUD fixtures (T4c) ────────────────────────────────────────────

const kCatalogWithSchema = <String, dynamic>{
  'id': 'cat-001',
  'slug': 'productos',
  'label': 'Productos',
  'name': 'Productos',
  'source_type': 'manual',
  'item_count': 2,
  'last_synced_at': null,
  'sync_status': 'manual',
  'primary_key': 'sku',
  'display_field': 'nombre',
  'fields_schema': [
    {
      'key': 'sku',
      'label': 'SKU',
      'type': 'text',
      'searchable': true,
      'is_primary': true,
    },
    {
      'key': 'nombre',
      'label': 'Nombre',
      'type': 'text',
      'searchable': true,
      'is_primary': false,
    },
  ],
};

const kItemsPage = <String, dynamic>{
  'items': kCatalogItems,
  'total': 2,
  'page': 1,
  'pages': 1,
};

const kCreatedItem = <String, dynamic>{
  'id': 'item-new-001',
  'data': {'sku': 'C300', 'nombre': 'Widget C'},
};

const kDeletedItemResponse = <String, dynamic>{
  'id': 'item-001',
  'unlinked_assignment_resources': 0,
};

// ── Detail tabs fixtures (T4d) ──────────────────────────────────────────────

const kCatalogGoogleSheets = <String, dynamic>{
  'id': 'cat-002',
  'slug': 'sucursales',
  'label': 'Sucursales',
  'name': 'Sucursales',
  'source_type': 'google_sheets',
  'item_count': 5,
  'last_synced_at': '2026-06-01T10:00:00Z',
  'sync_status': 'synced',
  'sheet_url': 'https://docs.google.com/spreadsheets/d/abc123/edit',
  'sheet_name': 'Sheet1',
  'source_config': {
    'sheet_url': 'https://docs.google.com/spreadsheets/d/abc123/edit',
    'sheet_name': 'Sheet1',
  },
  'primary_key': 'id',
  'display_field': 'nombre',
  'fields_schema': [
    {'key': 'id', 'label': 'ID', 'type': 'text', 'is_primary': true},
    {'key': 'nombre', 'label': 'Nombre', 'type': 'text', 'is_primary': false},
  ],
};

const kSyncLogRunning = <Map<String, dynamic>>[
  {
    'id': 'log-run-001',
    'status': 'running',
    'started_at': '2026-06-08T10:00:00Z',
    'triggered_by': 'manual',
  },
];

const kSyncLogSuccess = <Map<String, dynamic>>[
  {
    'id': 'log-run-001',
    'status': 'success',
    'started_at': '2026-06-08T10:00:00Z',
    'finished_at': '2026-06-08T10:00:03Z',
    'duration_ms': 3000,
    'items_added': 2,
    'items_updated': 1,
    'items_deleted': 0,
    'triggered_by': 'manual',
  },
];

// ── Preview column_specs fixtures (PLA-241) ─────────────────────────────────

const kSheetsPreviewWithSpecs = <String, dynamic>{
  'sheets': ['Sheet1'],
  'selected_sheet': 'Sheet1',
  'columns': ['N. de Venta', 'Número', '  Doble  Espacio  '],
  'column_specs': [
    {'header': 'N. de Venta', 'key': 'n_de_venta'},
    {'header': 'Número', 'key': 'numero'},
    {'header': '  Doble  Espacio  ', 'key': 'doble_espacio'},
  ],
};

const kSheetsPreviewLegacy = <String, dynamic>{
  'sheets': ['Sheet1'],
  'selected_sheet': 'Sheet1',
  'columns': ['N. de Venta', 'Número', '  Doble  Espacio  '],
};
