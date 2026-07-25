import 'package:flutter_test/flutter_test.dart';
import 'package:godrive_rider/main.dart';

void main() {
  testWidgets('Rider app boots', (tester) async {
    await tester.pumpWidget(const RiderApp());
    await tester.pump();
    expect(find.byType(RiderApp), findsOneWidget);
  });
}
