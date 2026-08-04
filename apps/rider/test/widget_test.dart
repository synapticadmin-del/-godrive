import 'package:flutter_test/flutter_test.dart';
import 'package:tempo_rider/main.dart';

void main() {
  testWidgets('Rider app boots', (tester) async {
    await tester.pumpWidget(const RiderApp());

    // The splash drives its entrance animations through flutter_animate, which
    // schedules timers as soon as the widgets mount. A bare `pump()` leaves
    // those timers pending and the test tears down mid-animation, which is why
    // this check failed with "Pending timers" rather than for any real boot
    // problem. Advancing the clock past the intro lets them retire.
    //
    // pumpAndSettle is deliberately avoided: the splash also runs a safety
    // timer for the intro video, and settling would block on work this
    // smoke test does not care about.
    await tester.pump(const Duration(seconds: 3));

    expect(find.byType(RiderApp), findsOneWidget);
  });
}
