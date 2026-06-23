import 'package:flutter_test/flutter_test.dart';
import 'package:nju_calendar_importer_flutter/models/nju_course.dart';
import 'package:nju_calendar_importer_flutter/services/calendar_sync_service.dart';

void main() {
  test('overwrite range expands fetched schedule to week Monday through Sunday',
      () {
    final bundle = ScheduleBundle(
      semesterId: '2025-2026-2',
      semesterName: '2025-2026瀛﹀勾 绗?瀛︽湡',
      semesterStart: DateTime(2026, 3, 2),
      semesterEnd:
          DateTime(2026, 7, 6).subtract(const Duration(milliseconds: 1)),
      courseCount: 2,
      examCount: 0,
      events: [
        NjuCourseEvent(
          title: 'Data Structures',
          start: DateTime(2026, 3, 4, 8),
          end: DateTime(2026, 3, 4, 9, 40),
          location: 'A101',
          description: 'course',
          importKey: 'course-1',
        ),
        NjuCourseEvent(
          title: 'Operating Systems',
          start: DateTime(2026, 6, 16, 10),
          end: DateTime(2026, 6, 16, 11, 40),
          location: 'B202',
          description: 'course',
          importKey: 'course-2',
        ),
      ],
    );

    final range = CalendarSyncService.overwriteRangeFor(bundle);

    expect(range.start, DateTime(2026, 3, 2));
    expect(range.end, DateTime(2026, 6, 21, 23, 59, 59, 999));
  });
}
