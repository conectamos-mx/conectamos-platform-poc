import 'package:conectamos_platform/core/storage/key_value_store.dart';

/// In-memory [KeyValueStore] for tests. No dart:html dependency.
class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _data = {};

  @override
  String? getString(String key) => _data[key];

  @override
  void setString(String key, String value) => _data[key] = value;

  @override
  void remove(String key) => _data.remove(key);
}
