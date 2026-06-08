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
    'type': 'flow',
    'id': 'flow-001',
    'name': 'Flujo de ventas',
  },
];
