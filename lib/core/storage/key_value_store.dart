import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Platform-agnostic synchronous key-value storage.
/// Production uses [WebKeyValueStore] (dart:html localStorage).
/// Tests can provide an in-memory implementation via provider override.
abstract class KeyValueStore {
  String? getString(String key);
  void setString(String key, String value);
  void remove(String key);
}

/// Must be overridden in the root ProviderScope (see main.dart).
final keyValueStoreProvider = Provider<KeyValueStore>((ref) {
  throw UnimplementedError(
    'keyValueStoreProvider must be overridden in ProviderScope',
  );
});
