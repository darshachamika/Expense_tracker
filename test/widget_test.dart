import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/main.dart';

void main() {
  testWidgets('Firebase setup failure shows recovery instructions', (tester) async {
    await tester.pumpWidget(const FirebaseErrorApp());

    expect(find.textContaining('Firebase setup could not finish.'), findsOneWidget);
    expect(find.textContaining('Check the terminal output'), findsOneWidget);
  });
}
