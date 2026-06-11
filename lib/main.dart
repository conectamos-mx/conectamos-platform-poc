import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/api/api_client.dart';
import 'core/build_info.dart';
import 'core/router/app_router.dart';
import 'core/storage/key_value_store.dart';
import 'core/storage/web_key_value_store.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/tz_format.dart';

const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: '',
);
const supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: '',
);

Future<void> main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('build: $kBuildMarker');

  await initializeDateFormatting('es_MX', null);
  await initializeDateFormatting('es', null);
  initTz();

  assert(ApiClient.baseUrl.isNotEmpty,
      'API_BASE_URL no está definida. Usa run_dev.sh para correr en local.');
  assert(supabaseUrl.isNotEmpty, 'SUPABASE_URL no está definida. Usa run_dev.sh.');
  assert(supabaseAnonKey.isNotEmpty, 'SUPABASE_ANON_KEY no está definida. Usa run_dev.sh.');

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  final store = WebKeyValueStore();

  runApp(
    ProviderScope(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
      ],
      child: const ConectamosApp(),
    ),
  );
}

class ConectamosApp extends ConsumerWidget {
  const ConectamosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'ConectamOS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
