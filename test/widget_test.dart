import 'package:flutter_test/flutter_test.dart';
import 'package:mbb/core/money.dart';

void main() {
  test('Money : fumée', () => expect(const Money(150).format(), '1,50'));
}
