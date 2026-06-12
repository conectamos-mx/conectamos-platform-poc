// Replicates the bootstrap sequence from lib/main.dart:29-52 without
// importing or calling main() directly. This is necessary because main()
// calls WidgetsFlutterBinding.ensureInitialized() which conflicts with
// IntegrationTestWidgetsFlutterBinding, and also calls usePathUrlStrategy()
// which is irrelevant in test context.
//
// Sequence mirrored from main.dart (verified against git rev 9b1bb87):
//   L29-30: initializeDateFormatting('es_MX'/'es')
//   L31:    initTz()
//   L38-41: Supabase.initialize(url, anonKey)
//   L43:    WebKeyValueStore()
//   L45-52: ProviderScope + ConectamosApp

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:conectamos_platform/core/storage/key_value_store.dart';
import 'package:conectamos_platform/core/storage/web_key_value_store.dart';
import 'package:conectamos_platform/core/utils/tz_format.dart';
import 'package:conectamos_platform/main.dart'
    show ConectamosApp, supabaseUrl, supabaseAnonKey;

/// Initializes Supabase + locale + timezone and returns the production
/// widget tree. Call once from setUpAll(); pass the result to pumpWidget().
///
/// Does NOT override supabaseClientProvider, authStateProvider, or
/// apiClientProvider — all providers use production defaults so every
/// network call goes through the real Dio + real Supabase session.
Future<Widget> buildSmokeTestApp() async {
  // Locale data (mirrors main.dart:29-30)
  await initializeDateFormatting('es_MX', null);
  await initializeDateFormatting('es', null);

  // Timezone database (mirrors main.dart:31)
  initTz();

  // Real Supabase client (mirrors main.dart:38-41).
  // supabaseUrl / supabaseAnonKey are compile-time consts read from
  // --dart-define=SUPABASE_URL / SUPABASE_ANON_KEY in the flutter drive
  // command, so they carry the dev values without any hardcoding.
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  // Production key-value store (localStorage). Mirrors main.dart:43-52.
  final store = WebKeyValueStore();

  return ProviderScope(
    overrides: [
      keyValueStoreProvider.overrideWithValue(store),
    ],
    child: const ConectamosApp(),
  );
}
