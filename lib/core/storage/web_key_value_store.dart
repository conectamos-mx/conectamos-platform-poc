// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'key_value_store.dart';

/// Browser localStorage implementation of [KeyValueStore].
class WebKeyValueStore implements KeyValueStore {
  @override
  String? getString(String key) => html.window.localStorage[key];

  @override
  void setString(String key, String value) {
    html.window.localStorage[key] = value;
  }

  @override
  void remove(String key) {
    html.window.localStorage.remove(key);
  }
}
