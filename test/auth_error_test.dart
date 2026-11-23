import 'package:finbiz/data/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('API exceptions remain readable', () {
    const error = ApiException(403, 'Forbidden');
    expect(error.statusCode, 403);
    expect(error.message, 'Forbidden');
  });
}
