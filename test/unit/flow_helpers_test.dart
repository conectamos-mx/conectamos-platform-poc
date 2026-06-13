import 'package:flutter_test/flutter_test.dart';
import 'package:conectamos_platform/core/utils/flow_helpers.dart';

void main() {
  group('isQueryFlow', () {
    test('returns false for empty flow', () {
      expect(isQueryFlow(<String, dynamic>{}), isFalse);
    });

    test('returns false when behavior is empty map', () {
      expect(isQueryFlow({'behavior': <String, dynamic>{}}), isFalse);
    });

    test('returns false for capture flow with conditions', () {
      expect(
        isQueryFlow({'behavior': {'conditions': <dynamic>[]}}),
        isFalse,
      );
    });

    test('returns true when behavior contains query_config', () {
      expect(
        isQueryFlow({
          'behavior': {
            'query_config': {
              'catalog_slug': 'orders',
              'metrics': <dynamic>[],
              'filter_fields': <dynamic>[],
              'group_by_fields': <dynamic>[],
            },
          },
        }),
        isTrue,
      );
    });

    test('returns false when behavior is not a Map', () {
      expect(isQueryFlow({'behavior': 'scheduled'}), isFalse);
    });

    test('returns false when behavior is null', () {
      expect(isQueryFlow({'behavior': null}), isFalse);
    });

    test('returns false when flow has no behavior key', () {
      expect(isQueryFlow({'name': 'test'}), isFalse);
    });
  });
}
