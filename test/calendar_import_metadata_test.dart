import 'package:flutter_test/flutter_test.dart';
import 'package:nju_calendar_importer_flutter/services/calendar_import_metadata.dart';

void main() {
  test('builds new importer description with semester id and details', () {
    final description = CalendarImportMetadata.buildDescription(
      semesterId: '2025-2026-2',
      importKey: 'abc123',
      detailLines: const ['学校：本科生', '教师：Alice'],
    );

    expect(description, contains(CalendarImportMetadata.currentMarker));
    expect(description, contains('semester_id=2025-2026-2'));
    expect(description, contains('import_key=abc123'));
    expect(description, contains('教师：Alice'));
  });

  test('parses current marker and semester id', () {
    final metadata = CalendarImportMetadata.parse('''
[NJU_CALENDAR_IMPORTER]
semester_id=2025-2026-2
import_key=abc123
''');

    expect(metadata.isGeneratedByApp, isTrue);
    expect(metadata.semesterId, '2025-2026-2');
    expect(metadata.isLegacy, isFalse);
  });

  test('parses legacy marker without semester id', () {
    final metadata = CalendarImportMetadata.parse('''
[NJU_SCHEDULE_IMPORT]
import_key=old
''');

    expect(metadata.isGeneratedByApp, isTrue);
    expect(metadata.semesterId, isNull);
    expect(metadata.isLegacy, isTrue);
  });

  test('overwrite matching keeps other semester events', () {
    expect(
      CalendarImportMetadata.shouldDeleteForSemesterOverwrite(
        description: '''
[NJU_CALENDAR_IMPORTER]
semester_id=2025-2026-1
''',
        selectedSemesterId: '2025-2026-2',
      ),
      isFalse,
    );
  });

  test('overwrite matching deletes same semester and legacy generated events', () {
    expect(
      CalendarImportMetadata.shouldDeleteForSemesterOverwrite(
        description: '''
[NJU_CALENDAR_IMPORTER]
semester_id=2025-2026-2
''',
        selectedSemesterId: '2025-2026-2',
      ),
      isTrue,
    );

    expect(
      CalendarImportMetadata.shouldDeleteForSemesterOverwrite(
        description: '[NJU_SCHEDULE_IMPORT]\nimport_key=old',
        selectedSemesterId: '2025-2026-2',
      ),
      isTrue,
    );
  });

  test('groups generated events by semester id and legacy bucket', () {
    final groups = CalendarImportMetadata.groupGeneratedEvents([
      const ImportedCalendarEvent(
        deleteId: '1',
        calendarId: 'cal-a',
        calendarName: 'Personal',
        description: '[NJU_CALENDAR_IMPORTER]\nsemester_id=2025-2026-2',
      ),
      const ImportedCalendarEvent(
        deleteId: '2',
        calendarId: 'cal-a',
        calendarName: 'Personal',
        description: '[NJU_SCHEDULE_IMPORT]\nimport_key=old',
      ),
      const ImportedCalendarEvent(
        deleteId: '3',
        calendarId: 'cal-b',
        calendarName: 'School',
        description: 'manual event',
      ),
    ]);

    expect(groups.length, 2);
    expect(groups[0].semesterId, '2025-2026-2');
    expect(groups[0].label, '2025-2026-2');
    expect(groups[0].events.single.deleteId, '1');
    expect(groups[1].semesterId, isNull);
    expect(groups[1].label, '旧版本导入（未记录学期）');
    expect(groups[1].events.single.deleteId, '2');
  });
}
