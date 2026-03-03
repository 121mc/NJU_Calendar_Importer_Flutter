import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nju_calendar_importer_flutter/main.dart';

void main() {
  testWidgets('app bootstraps smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const NjuScheduleCalendarApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(HomePage), findsOneWidget);
  });
}
