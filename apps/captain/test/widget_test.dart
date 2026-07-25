import 'package:flutter_test/flutter_test.dart';
import 'package:synaptic_go_captain/main.dart';

void main() {
  testWidgets('Captain app boots', (tester) async {
    await tester.pumpWidget(const CaptainApp());
    await tester.pump();
    expect(find.byType(CaptainApp), findsOneWidget);
  });
}
