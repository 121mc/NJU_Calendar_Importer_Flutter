import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nju_schedule_calendar/main.dart';

void main() {
  testWidgets('app bootstraps smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const NjuScheduleCalendarApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(HomePage), findsOneWidget);
  });
}
