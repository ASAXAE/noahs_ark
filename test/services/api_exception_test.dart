import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/services/api_exception.dart';

void main() {
  group('ApiException', () {
    test('treats 401 as unauthorized', () {
      const error = ApiException(
        statusCode: 401,
        message: 'Invalid or expired token',
      );

      expect(error.isUnauthorized, isTrue);
    });

    test('does not treat other HTTP errors as unauthorized', () {
      const error = ApiException(
        statusCode: 500,
        message: 'Internal server error',
      );

      expect(error.isUnauthorized, isFalse);
    });

    test('keeps ordinary network errors separate', () {
      final networkError = Exception('Network unavailable');

      expect(networkError, isNot(isA<ApiException>()));
    });
  });
}
