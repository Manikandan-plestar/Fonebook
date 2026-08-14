import 'package:flutter_test/flutter_test.dart';
import 'package:fonebook/main.dart';
import 'package:fonebook/models/user_session.dart';

void main() {
  testWidgets('Fone Book app smoke test', (tester) async {
    // Provide a null session to start at Login
    await tester.pumpWidget(const FonebookApp(initialSession: UserSession()));
    await tester.pump();

    // Verify Login screen elements
    expect(find.text('Fone Book'), findsAtLeast(1));
    expect(find.text('Send otp'), findsOneWidget);
  });
}
