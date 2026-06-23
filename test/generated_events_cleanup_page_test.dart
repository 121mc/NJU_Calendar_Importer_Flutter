import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nju_calendar_importer_flutter/pages/generated_events_cleanup_page.dart';
import 'package:nju_calendar_importer_flutter/services/calendar_import_metadata.dart';
import 'package:nju_calendar_importer_flutter/services/calendar_sync_service.dart';

class CleanupFakeCalendarSyncService extends CalendarSyncService {
  CleanupFakeCalendarSyncService(this.groups);

  List<GeneratedEventsGroup> groups;
  final deletedGroups = <String>[];
  var deletedAll = false;

  @override
  Future<List<GeneratedEventsGroup>> scanGeneratedEventGroups() async => groups;

  @override
  Future<int> deleteGeneratedEventGroup(GeneratedEventsGroup group) async {
    deletedGroups.add(group.label);
    groups = groups.where((item) => item.label != group.label).toList();
    return group.count;
  }

  @override
  Future<int> deleteGeneratedEventGroups(
    List<GeneratedEventsGroup> groupsToDelete,
  ) async {
    deletedAll = true;
    final labels = groupsToDelete.map((group) => group.label).toSet();
    final deleted =
        groupsToDelete.fold<int>(0, (sum, group) => sum + group.count);
    groups = groups.where((group) => !labels.contains(group.label)).toList();
    return deleted;
  }
}

GeneratedEventsGroup _group({
  required String? semesterId,
  required String label,
  required String deleteId,
  required String description,
}) {
  return GeneratedEventsGroup(
    semesterId: semesterId,
    label: label,
    events: [
      ImportedCalendarEvent(
        deleteId: deleteId,
        calendarId: 'cal',
        calendarName: 'Personal',
        description: description,
      ),
    ],
  );
}

void main() {
  testWidgets(
    'cleanup page lists semester groups and supports deleting one group',
    (tester) async {
      final service = CleanupFakeCalendarSyncService([
        _group(
          semesterId: '2025-2026-2',
          label: '2025-2026-2',
          deleteId: '1',
          description: '[NJU_CALENDAR_IMPORTER]\nsemester_id=2025-2026-2',
        ),
        _group(
          semesterId: null,
          label: CalendarImportMetadata.legacyGroupLabel,
          deleteId: '2',
          description: '[NJU_SCHEDULE_IMPORT]',
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: GeneratedEventsCleanupPage(calendarSyncService: service),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2025-2026-2'), findsOneWidget);
      expect(
          find.text(CalendarImportMetadata.legacyGroupLabel), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, '删除').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '确认删除'));
      await tester.pumpAndSettle();

      expect(service.deletedGroups, contains('2025-2026-2'));
      expect(find.text('2025-2026-2'), findsNothing);
      expect(
          find.text(CalendarImportMetadata.legacyGroupLabel), findsOneWidget);
    },
  );

  testWidgets('cleanup page supports deleting all scanned groups',
      (tester) async {
    final service = CleanupFakeCalendarSyncService([
      _group(
        semesterId: '2025-2026-2',
        label: '2025-2026-2',
        deleteId: '1',
        description: '[NJU_CALENDAR_IMPORTER]\nsemester_id=2025-2026-2',
      ),
      _group(
        semesterId: null,
        label: CalendarImportMetadata.legacyGroupLabel,
        deleteId: '2',
        description: '[NJU_SCHEDULE_IMPORT]',
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: GeneratedEventsCleanupPage(calendarSyncService: service),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '全部删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认删除'));
    await tester.pumpAndSettle();

    expect(service.deletedAll, isTrue);
    expect(find.text('没有扫描到本软件生成的日程。'), findsOneWidget);
  });
}
