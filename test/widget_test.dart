import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mbb/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MBB démarre', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MbbApp());
    await tester.pump();
    expect(find.byType(MbbApp), findsOneWidget);
  });
}
