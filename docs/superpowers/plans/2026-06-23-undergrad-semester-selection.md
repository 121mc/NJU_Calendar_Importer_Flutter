# Undergrad Semester Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build本科生学期选择拉课表、新旧日历标记兼容、按学期覆盖删除，以及独立的本软件日程删除管理入口。

**Architecture:** Add a small semester model and calendar-import metadata helpers first, then wire `NjuScheduleService` to fetch本科可选学期 and selected-semester schedules. Keep UI state in `HomePage`, and move cleanup into a dedicated page backed by `CalendarSyncService` scan/delete methods.

**Tech Stack:** Flutter, Dart, Dio, device_calendar_plus, flutter_test.

---

## File Structure

- Create `lib/models/nju_semester.dart`: pure model for本科学期选项, display names, and semester date ranges.
- Modify `lib/models/nju_course.dart`: add `semesterId`, `semesterStart`, and `semesterEnd` to `ScheduleBundle`.
- Create `lib/services/calendar_import_metadata.dart`: constants, description builder, metadata parser, deletion matching, and grouping models.
- Modify `lib/services/nju_schedule_service.dart`: add本科 semester-list and selected-semester fetch APIs while keeping existing public API for研究生.
- Modify `lib/services/calendar_sync_service.dart`: use the new marker, selected-semester overwrite range, old-marker compatibility, and generated-event scan/delete APIs.
- Create `lib/pages/generated_events_cleanup_page.dart`: full-screen cleanup UI that scans all readable calendars and deletes selected groups or all generated events.
- Modify `lib/main.dart`: stop auto-fetching schedules after login, add the semester-selection card, show sync card only after a non-empty selected-semester fetch, and always show cleanup card at the bottom.
- Create `test/nju_semester_test.dart`: pure semester parsing/date tests.
- Create `test/calendar_import_metadata_test.dart`: marker, semester id parsing, overwrite matching, and grouping tests.
- Create `test/nju_schedule_service_undergrad_test.dart`: fake-Dio tests for本科 semester options and selected semester request parameters.
- Modify `test/calendar_sync_service_test.dart`: update `ScheduleBundle` construction and overwrite-range expectations.
- Modify `test/widget_test.dart`: add mock service injection tests for logged-in semester UI and bottom cleanup card.

## Task 1: Semester Model And Bundle Metadata

**Files:**
- Create: `lib/models/nju_semester.dart`
- Modify: `lib/models/nju_course.dart`
- Create: `test/nju_semester_test.dart`
- Modify: `test/calendar_sync_service_test.dart`

- [ ] **Step 1: Write failing semester model tests**

Create `test/nju_semester_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nju_calendar_importer_flutter/models/nju_semester.dart';

void main() {
  test('parses undergrad normal semester row into id name and range', () {
    final semester = NjuSemester.fromUndergradRow(
      {
        'XN': '2025-2026',
        'XQ': '2',
        'XQKSRQ': '2026-03-02 00:00:00',
        'ZZC': 18,
      },
      currentSemesterId: '2025-2026-2',
    );

    expect(semester.id, '2025-2026-2');
    expect(semester.name, '2025-2026学年 第2学期');
    expect(semester.year, '2025-2026');
    expect(semester.term, '2');
    expect(semester.start, DateTime(2026, 3, 2));
    expect(semester.end, DateTime(2026, 7, 6).subtract(const Duration(milliseconds: 1)));
    expect(semester.isCurrent, isTrue);
  });

  test('parses undergrad summer semester row with summer display name', () {
    final semester = NjuSemester.fromUndergradRow(
      {
        'XN': '2025-2026',
        'XQ': '3',
        'XQKSRQ': '2026-07-06 00:00:00',
        'ZZC': 4,
      },
      currentSemesterId: '2025-2026-2',
    );

    expect(semester.id, '2025-2026-3');
    expect(semester.name, '2025-2026学年 暑期');
    expect(semester.start, DateTime(2026, 7, 6));
    expect(semester.end, DateTime(2026, 8, 3).subtract(const Duration(milliseconds: 1)));
    expect(semester.isCurrent, isFalse);
  });

  test('parses current semester row id and name', () {
    final current = NjuSemester.currentUndergradIdAndName({
      'DM': '2025-2026-2',
      'MC': '2025-2026学年 第2学期',
    });

    expect(current.$1, '2025-2026-2');
    expect(current.$2, '2025-2026学年 第2学期');
  });
}
```

- [ ] **Step 2: Run semester model tests and verify they fail**

Run:

```powershell
flutter test test/nju_semester_test.dart
```

Expected: FAIL because `lib/models/nju_semester.dart` does not exist.

- [ ] **Step 3: Implement the semester model**

Create `lib/models/nju_semester.dart`:

```dart
class NjuSemester {
  const NjuSemester({
    required this.id,
    required this.name,
    required this.year,
    required this.term,
    required this.start,
    required this.end,
    required this.isCurrent,
  });

  final String id;
  final String name;
  final String year;
  final String term;
  final DateTime start;
  final DateTime end;
  final bool isCurrent;

  factory NjuSemester.fromUndergradRow(
    Map<String, dynamic> row, {
    required String? currentSemesterId,
  }) {
    final year = '${row['XN'] ?? ''}'.trim();
    final term = '${row['XQ'] ?? ''}'.trim();
    final id = '$year-$term';
    final start = _parseDateOnly('${row['XQKSRQ'] ?? ''}');
    final weekCount = int.tryParse('${row['ZZC'] ?? ''}') ?? 0;
    final safeWeekCount = weekCount <= 0 ? 1 : weekCount;

    return NjuSemester(
      id: id,
      name: '$year学年 ${_termDisplayName(term)}',
      year: year,
      term: term,
      start: start,
      end: start
          .add(Duration(days: safeWeekCount * DateTime.daysPerWeek))
          .subtract(const Duration(milliseconds: 1)),
      isCurrent: id == currentSemesterId,
    );
  }

  static (String, String) currentUndergradIdAndName(Map<String, dynamic> row) {
    final id = '${row['DM'] ?? ''}'.trim();
    final name = '${row['MC'] ?? id}'.trim();
    return (id, name.isEmpty ? id : name);
  }

  static String _termDisplayName(String term) {
    switch (term) {
      case '1':
        return '第1学期';
      case '2':
        return '第2学期';
      case '3':
        return '暑期';
      default:
        return '第$term学期';
    }
  }

  static DateTime _parseDateOnly(String text) {
    final clean = text.trim();
    if (clean.length < 10) {
      throw FormatException('Invalid semester start date: $text');
    }
    return DateTime.parse(clean.substring(0, 10));
  }
}
```

- [ ] **Step 4: Update `ScheduleBundle` metadata**

Modify `lib/models/nju_course.dart` so `ScheduleBundle` is:

```dart
class ScheduleBundle {
  ScheduleBundle({
    required this.semesterId,
    required this.semesterName,
    required this.semesterStart,
    required this.semesterEnd,
    required this.events,
    required this.courseCount,
    required this.examCount,
  });

  final String semesterId;
  final String semesterName;
  final DateTime semesterStart;
  final DateTime semesterEnd;
  final List<NjuCourseEvent> events;
  final int courseCount;
  final int examCount;

  DateTime? get earliestStart {
    if (events.isEmpty) return null;
    return events.map((e) => e.start).reduce((a, b) => a.isBefore(b) ? a : b);
  }

  DateTime? get latestEnd {
    if (events.isEmpty) return null;
    return events.map((e) => e.end).reduce((a, b) => a.isAfter(b) ? a : b);
  }
}
```

- [ ] **Step 5: Update existing calendar sync test fixture**

In `test/calendar_sync_service_test.dart`, add metadata to the `ScheduleBundle` constructor:

```dart
final bundle = ScheduleBundle(
  semesterId: '2025-2026-2',
  semesterName: '2025-2026学年 第2学期',
  semesterStart: DateTime(2026, 3, 2),
  semesterEnd: DateTime(2026, 7, 6).subtract(const Duration(milliseconds: 1)),
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
```

- [ ] **Step 6: Run tests and verify Task 1 passes**

Run:

```powershell
flutter test test/nju_semester_test.dart test/calendar_sync_service_test.dart
```

Expected: PASS for `nju_semester_test.dart`; `calendar_sync_service_test.dart` may still fail if `overwriteRangeFor` has not been updated. If it fails only because the expected overwrite range is still event-derived, leave that failure for Task 3.

- [ ] **Step 7: Commit Task 1**

```powershell
git add lib/models/nju_semester.dart lib/models/nju_course.dart test/nju_semester_test.dart test/calendar_sync_service_test.dart
git commit -m "feat: add undergrad semester model"
```

## Task 2: Calendar Import Metadata Helpers

**Files:**
- Create: `lib/services/calendar_import_metadata.dart`
- Create: `test/calendar_import_metadata_test.dart`

- [ ] **Step 1: Write failing metadata tests**

Create `test/calendar_import_metadata_test.dart`:

```dart
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
```

- [ ] **Step 2: Run metadata tests and verify they fail**

Run:

```powershell
flutter test test/calendar_import_metadata_test.dart
```

Expected: FAIL because `calendar_import_metadata.dart` does not exist.

- [ ] **Step 3: Implement metadata helpers**

Create `lib/services/calendar_import_metadata.dart`:

```dart
class CalendarImportMetadata {
  const CalendarImportMetadata({
    required this.isGeneratedByApp,
    required this.isLegacy,
    required this.semesterId,
  });

  static const currentMarker = '[NJU_CALENDAR_IMPORTER]';
  static const legacyMarker = '[NJU_SCHEDULE_IMPORT]';
  static const legacyGroupLabel = '旧版本导入（未记录学期）';

  final bool isGeneratedByApp;
  final bool isLegacy;
  final String? semesterId;

  static String buildDescription({
    required String semesterId,
    required String importKey,
    required Iterable<String> detailLines,
  }) {
    return [
      currentMarker,
      'semester_id=$semesterId',
      'import_key=$importKey',
      ...detailLines.where((line) => line.trim().isNotEmpty),
    ].join('\n');
  }

  static CalendarImportMetadata parse(String? description) {
    final text = description ?? '';
    final hasCurrentMarker = text.contains(currentMarker);
    final hasLegacyMarker = text.contains(legacyMarker);
    final semesterId = RegExp(r'^semester_id=(.+)$', multiLine: true)
        .firstMatch(text)
        ?.group(1)
        ?.trim();

    return CalendarImportMetadata(
      isGeneratedByApp: hasCurrentMarker || hasLegacyMarker,
      isLegacy: hasLegacyMarker && !hasCurrentMarker,
      semesterId: semesterId == null || semesterId.isEmpty ? null : semesterId,
    );
  }

  static bool shouldDeleteForSemesterOverwrite({
    required String? description,
    required String selectedSemesterId,
  }) {
    final metadata = parse(description);
    if (!metadata.isGeneratedByApp) {
      return false;
    }
    if (metadata.semesterId == null) {
      return true;
    }
    return metadata.semesterId == selectedSemesterId;
  }

  static List<GeneratedEventsGroup> groupGeneratedEvents(
    Iterable<ImportedCalendarEvent> events,
  ) {
    final grouped = <String, List<ImportedCalendarEvent>>{};
    for (final event in events) {
      final metadata = parse(event.description);
      if (!metadata.isGeneratedByApp) {
        continue;
      }
      final key = metadata.semesterId ?? '';
      grouped.putIfAbsent(key, () => []).add(event);
    }

    final groups = grouped.entries.map((entry) {
      final semesterId = entry.key.isEmpty ? null : entry.key;
      return GeneratedEventsGroup(
        semesterId: semesterId,
        label: semesterId ?? legacyGroupLabel,
        events: List.unmodifiable(entry.value),
      );
    }).toList();

    groups.sort((a, b) {
      if (a.semesterId == null && b.semesterId != null) return 1;
      if (a.semesterId != null && b.semesterId == null) return -1;
      return b.label.compareTo(a.label);
    });
    return groups;
  }
}

class ImportedCalendarEvent {
  const ImportedCalendarEvent({
    required this.deleteId,
    required this.calendarId,
    required this.calendarName,
    required this.description,
  });

  final String deleteId;
  final String calendarId;
  final String calendarName;
  final String? description;
}

class GeneratedEventsGroup {
  const GeneratedEventsGroup({
    required this.semesterId,
    required this.label,
    required this.events,
  });

  final String? semesterId;
  final String label;
  final List<ImportedCalendarEvent> events;

  int get count => events.length;
}
```

- [ ] **Step 4: Run metadata tests and verify they pass**

Run:

```powershell
flutter test test/calendar_import_metadata_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit Task 2**

```powershell
git add lib/services/calendar_import_metadata.dart test/calendar_import_metadata_test.dart
git commit -m "feat: add calendar import metadata helpers"
```

## Task 3: Calendar Sync Range And Marker Compatibility

**Files:**
- Modify: `lib/services/calendar_sync_service.dart`
- Modify: `test/calendar_sync_service_test.dart`

- [ ] **Step 1: Write failing calendar sync tests**

Add these tests to `test/calendar_sync_service_test.dart`:

```dart
test('overwrite range uses official semester boundaries when present', () {
  final bundle = ScheduleBundle(
    semesterId: '2025-2026-2',
    semesterName: '2025-2026学年 第2学期',
    semesterStart: DateTime(2026, 3, 2),
    semesterEnd: DateTime(2026, 7, 6).subtract(const Duration(milliseconds: 1)),
    courseCount: 0,
    examCount: 0,
    events: [
      NjuCourseEvent(
        title: 'Short Course',
        start: DateTime(2026, 4, 1, 8),
        end: DateTime(2026, 4, 1, 9),
        location: 'A101',
        description: 'course',
        importKey: 'course-1',
      ),
    ],
  );

  final range = CalendarSyncService.overwriteRangeFor(bundle);

  expect(range.start, DateTime(2026, 3, 2));
  expect(range.end, DateTime(2026, 7, 6).subtract(const Duration(milliseconds: 1)));
});

test('empty bundle still uses semester boundaries for overwrite range', () {
  final bundle = ScheduleBundle(
    semesterId: '2025-2026-2',
    semesterName: '2025-2026学年 第2学期',
    semesterStart: DateTime(2026, 3, 2),
    semesterEnd: DateTime(2026, 7, 6).subtract(const Duration(milliseconds: 1)),
    courseCount: 0,
    examCount: 0,
    events: const [],
  );

  final range = CalendarSyncService.overwriteRangeFor(bundle);

  expect(range.start, DateTime(2026, 3, 2));
  expect(range.end, DateTime(2026, 7, 6).subtract(const Duration(milliseconds: 1)));
});
```

Update the existing `overwrite range expands fetched schedule...` test name to:

```dart
test('legacy fallback range expands fetched schedule to week Monday through Sunday', () {
```

In that test, set `semesterStart` and `semesterEnd` to `DateTime(1900)` to exercise fallback:

```dart
semesterStart: DateTime(1900),
semesterEnd: DateTime(1900),
```

- [ ] **Step 2: Run calendar sync tests and verify they fail**

Run:

```powershell
flutter test test/calendar_sync_service_test.dart
```

Expected: FAIL because `overwriteRangeFor` still derives range only from event dates or throws on an empty bundle.

- [ ] **Step 3: Update range and marker logic**

In `lib/services/calendar_sync_service.dart`:

1. Add the import:

```dart
import 'calendar_import_metadata.dart';
```

2. Replace marker constants with:

```dart
  static const importMarker = CalendarImportMetadata.currentMarker;
  static const legacyImportMarker = CalendarImportMetadata.legacyMarker;
```

3. Replace `overwriteRangeFor` with:

```dart
  static CalendarOverwriteRange overwriteRangeFor(ScheduleBundle bundle) {
    if (bundle.semesterEnd.isAfter(bundle.semesterStart)) {
      return CalendarOverwriteRange(
        start: bundle.semesterStart,
        end: bundle.semesterEnd,
      );
    }

    final earliest = bundle.earliestStart;
    final latest = bundle.latestEnd;
    if (earliest == null || latest == null) {
      throw StateError(
        'Cannot calculate overwrite range for an empty schedule.',
      );
    }

    final firstDay = DateTime(earliest.year, earliest.month, earliest.day);
    final lastDay = DateTime(latest.year, latest.month, latest.day);
    final monday = firstDay.subtract(
      Duration(days: firstDay.weekday - DateTime.monday),
    );
    final nextMonday = lastDay.add(
      Duration(days: DateTime.daysPerWeek - lastDay.weekday + 1),
    );
    final sundayEnd = nextMonday.subtract(const Duration(milliseconds: 1));

    return CalendarOverwriteRange(start: monday, end: sundayEnd);
  }
```

4. In the overwrite deletion loop inside `syncEvents`, replace:

```dart
if (description.contains(importMarker)) {
```

with:

```dart
if (CalendarImportMetadata.shouldDeleteForSemesterOverwrite(
  description: description,
  selectedSemesterId: bundle.semesterId,
)) {
```

- [ ] **Step 4: Run calendar sync tests and verify they pass**

Run:

```powershell
flutter test test/calendar_sync_service_test.dart test/calendar_import_metadata_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit Task 3**

```powershell
git add lib/services/calendar_sync_service.dart test/calendar_sync_service_test.dart
git commit -m "feat: use semester-aware calendar overwrite"
```

## Task 4: Selected-Semester Undergrad Fetching

**Files:**
- Modify: `lib/services/nju_schedule_service.dart`
- Create: `test/nju_schedule_service_undergrad_test.dart`

- [ ] **Step 1: Write failing service tests with fake Dio**

Create `test/nju_schedule_service_undergrad_test.dart`:

```dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nju_calendar_importer_flutter/models/login_models.dart';
import 'package:nju_calendar_importer_flutter/models/school_type.dart';
import 'package:nju_calendar_importer_flutter/services/auth_service.dart';
import 'package:nju_calendar_importer_flutter/services/nju_schedule_service.dart';
import 'package:nju_calendar_importer_flutter/services/storage_service.dart';

class FakeAuthService extends AuthService {
  FakeAuthService(this._dio) : super(StorageService());

  final Dio _dio;

  @override
  Future<Dio> buildAuthenticatedDio(SessionInfo session) async => _dio;
}

void main() {
  SessionInfo undergradSession() => const SessionInfo(
        username: 'student',
        schoolType: SchoolType.undergrad,
        cookiesByBaseUrl: {},
      );

  test('fetches undergrad semesters and marks current semester', () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.endsWith('/dqxnxq.do')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'datas': {
                      'dqxnxq': {
                        'rows': [
                          {'DM': '2025-2026-2', 'MC': '2025-2026学年 第2学期'},
                        ],
                      },
                    },
                    'code': '0',
                  },
                ),
              );
              return;
            }
            if (options.path.endsWith('/cxjcs.do')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'datas': {
                      'cxjcs': {
                        'rows': [
                          {
                            'XN': '2026-2027',
                            'XQ': '1',
                            'XQKSRQ': '2026-08-24 00:00:00',
                            'ZZC': 20,
                          },
                          {
                            'XN': '2025-2026',
                            'XQ': '2',
                            'XQKSRQ': '2026-03-02 00:00:00',
                            'ZZC': 18,
                          },
                        ],
                      },
                    },
                    'code': '0',
                  },
                ),
              );
              return;
            }
            handler.reject(DioException(requestOptions: options));
          },
        ),
      );

    final service = NjuScheduleService(FakeAuthService(dio));
    final result = await service.fetchUndergradSemesterOptions(undergradSession());

    expect(result.currentSemesterId, '2025-2026-2');
    expect(result.semesters.length, 2);
    expect(result.semesters.first.id, '2026-2027-1');
    expect(result.semesters[1].id, '2025-2026-2');
    expect(result.semesters[1].isCurrent, isTrue);
  });

  test('selected undergrad semester id is submitted to course and exam APIs', () async {
    final requests = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);

            if (options.path.endsWith('/cxxszhxqkb.do')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'datas': {
                      'cxxszhxqkb': {
                        'rows': <Map<String, dynamic>>[],
                      },
                    },
                    'code': '0',
                  },
                ),
              );
              return;
            }
            if (options.path.endsWith('/cxxsksap.do')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'datas': {
                      'cxxsksap': {
                        'rows': <Map<String, dynamic>>[],
                      },
                    },
                    'code': '0',
                  },
                ),
              );
              return;
            }
            handler.reject(DioException(requestOptions: options));
          },
        ),
      );

    final service = NjuScheduleService(FakeAuthService(dio));
    final semester = (await service.fetchUndergradScheduleForSemester(
      undergradSession(),
      semesterId: '2025-2026-1',
      semesterName: '2025-2026学年 第1学期',
      semesterStart: DateTime(2025, 8, 25),
      semesterEnd: DateTime(2026, 1, 12).subtract(const Duration(milliseconds: 1)),
      includeFinalExams: true,
    ));

    expect(semester.semesterId, '2025-2026-1');
    expect(semester.events, isEmpty);

    final courseRequest = requests.firstWhere(
      (request) => request.path.endsWith('/cxxszhxqkb.do'),
    );
    expect(courseRequest.data['XNXQDM'], '2025-2026-1');

    final examRequest = requests.firstWhere(
      (request) => request.path.endsWith('/cxxsksap.do'),
    );
    final examPayload = jsonDecode(examRequest.data['requestParamStr'] as String)
        as Map<String, dynamic>;
    expect(examPayload['XNXQDM'], '2025-2026-1');
  });
}
```

- [ ] **Step 2: Run service tests and verify they fail**

Run:

```powershell
flutter test test/nju_schedule_service_undergrad_test.dart
```

Expected: FAIL because `fetchUndergradSemesterOptions` and `fetchUndergradScheduleForSemester` do not exist.

- [ ] **Step 3: Add semester option result type and public APIs**

In `lib/services/nju_schedule_service.dart`, add:

```dart
import '../models/nju_semester.dart';
import 'calendar_import_metadata.dart';
```

Add this result class above `NjuScheduleService`:

```dart
class UndergradSemesterOptions {
  const UndergradSemesterOptions({
    required this.currentSemesterId,
    required this.currentSemesterName,
    required this.semesters,
  });

  final String currentSemesterId;
  final String currentSemesterName;
  final List<NjuSemester> semesters;

  NjuSemester? get currentSemester {
    for (final semester in semesters) {
      if (semester.id == currentSemesterId) {
        return semester;
      }
    }
    return semesters.isEmpty ? null : semesters.first;
  }
}
```

Add these public methods inside `NjuScheduleService`:

```dart
  Future<UndergradSemesterOptions> fetchUndergradSemesterOptions(
    SessionInfo session,
  ) async {
    final dio = await _authService.buildAuthenticatedDio(session);
    final current = await _fetchUndergradCurrentSemester(dio);
    final semesters = await _fetchUndergradSemesterList(
      dio,
      currentSemesterId: current.$1,
    );

    if (semesters.isEmpty) {
      throw Exception('本科-学期列表接口未返回可用学期。');
    }

    return UndergradSemesterOptions(
      currentSemesterId: current.$1,
      currentSemesterName: current.$2,
      semesters: semesters,
    );
  }

  Future<ScheduleBundle> fetchUndergradScheduleForSemester(
    SessionInfo session, {
    required String semesterId,
    required String semesterName,
    required DateTime semesterStart,
    required DateTime semesterEnd,
    bool includeFinalExams = true,
  }) async {
    final dio = await _authService.buildAuthenticatedDio(session);
    return _fetchUndergradForSemester(
      dio,
      semesterId: semesterId,
      semesterName: semesterName,
      semesterStart: semesterStart,
      semesterEnd: semesterEnd,
      includeFinalExams: includeFinalExams,
    );
  }
```

- [ ] **Step 4: Refactor existing本科 fetch to use selected semester**

In `_fetchUndergrad`, replace current-semester/list lookup code with:

```dart
    final current = await _fetchUndergradCurrentSemester(dio);
    final allSemesters = await _fetchUndergradSemesterList(
      dio,
      currentSemesterId: current.$1,
    );
    final semester = allSemesters.firstWhere(
      (item) => item.id == current.$1,
      orElse: () => throw Exception('未找到当前学期的起始日期。'),
    );

    return _fetchUndergradForSemester(
      dio,
      semesterId: semester.id,
      semesterName: current.$2,
      semesterStart: semester.start,
      semesterEnd: semester.end,
      includeFinalExams: includeFinalExams,
    );
```

Add private helpers:

```dart
  Future<(String, String)> _fetchUndergradCurrentSemester(Dio dio) async {
    final currentSemesterResp = await dio.get<dynamic>(
      'https://ehallapp.nju.edu.cn/jwapp/sys/wdkb/modules/jshkcb/dqxnxq.do',
    );
    final currentSemesterData = _ensureJsonMap(
      currentSemesterResp.data,
      apiName: '本科-当前学期接口',
    );
    final semesterRows = _readRows(
      currentSemesterData,
      ['datas', 'dqxnxq', 'rows'],
    );
    if (semesterRows.isEmpty) {
      throw Exception('本科-当前学期接口未返回 rows。可能是登录态失效，或接口结构发生变化。');
    }
    return NjuSemester.currentUndergradIdAndName(semesterRows.first);
  }

  Future<List<NjuSemester>> _fetchUndergradSemesterList(
    Dio dio, {
    required String? currentSemesterId,
  }) async {
    final allSemesterResp = await dio.get<dynamic>(
      'https://ehallapp.nju.edu.cn/jwapp/sys/wdkb/modules/jshkcb/cxjcs.do',
    );
    final allSemesterData = _ensureJsonMap(
      allSemesterResp.data,
      apiName: '本科-学期列表接口',
    );
    final allSemesterRows = _readRows(
      allSemesterData,
      ['datas', 'cxjcs', 'rows'],
    );
    return allSemesterRows
        .map(
          (row) => NjuSemester.fromUndergradRow(
            row,
            currentSemesterId: currentSemesterId,
          ),
        )
        .toList();
  }
```

Create `_fetchUndergradForSemester` with this selected-semester body:

```dart
  Future<ScheduleBundle> _fetchUndergradForSemester(
    Dio dio, {
    required String semesterId,
    required String semesterName,
    required DateTime semesterStart,
    required DateTime semesterEnd,
    required bool includeFinalExams,
  }) async {
    final coursesResp = await dio.post<dynamic>(
      'https://ehallapp.nju.edu.cn/jwapp/sys/wdkb/modules/xskcb/cxxszhxqkb.do',
      data: {
        'XNXQDM': semesterId,
        'pageSize': '9999',
        'pageNumber': '1',
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final coursesData = _ensureJsonMap(
      coursesResp.data,
      apiName: '本科-课表接口',
    );
    final courseRows = _readRows(
      coursesData,
      ['datas', 'cxxszhxqkb', 'rows'],
    );

    final events = <NjuCourseEvent>[];
    for (final row in courseRows) {
      events.addAll(_mapUndergradCourse(row, semesterStart, semesterId));
    }

    var examCount = 0;
    if (includeFinalExams) {
      final examsResp = await dio.post<dynamic>(
        'https://ehallapp.nju.edu.cn/jwapp/sys/studentWdksapApp/WdksapController/cxxsksap.do',
        data: {
          'requestParamStr': jsonEncode({
            'XNXQDM': semesterId,
            '*order': '-KSRQ,-KSSJMS',
          }),
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final examsData = _ensureJsonMap(
        examsResp.data,
        apiName: '本科-考试接口',
      );
      final examRows = _readRows(
        examsData,
        ['datas', 'cxxsksap', 'rows'],
      );
      examCount = examRows.length;
      for (final row in examRows) {
        final event = _mapUndergradExam(row, semesterId);
        if (event != null) {
          events.add(event);
        }
      }
    }

    events.sort((a, b) => a.start.compareTo(b.start));

    return ScheduleBundle(
      semesterId: semesterId,
      semesterName: semesterName,
      semesterStart: semesterStart,
      semesterEnd: semesterEnd,
      events: events,
      courseCount: courseRows.length,
      examCount: examCount,
    );
  }
```

- [ ] **Step 5: Add semester id to generated descriptions**

Change `_mapUndergradCourse`, `_mapUndergradExam`, and `_mapGraduateCourse` signatures to accept `semesterId`. For本科 call sites, pass the selected `semesterId`.

Replace `_buildDescription` body with:

```dart
    final sanitizedTeacher = _sanitizeTeacher(teacher);
    final detailLines = [
      '学校：$schoolLabel',
      if (sanitizedTeacher != null && sanitizedTeacher.isNotEmpty)
        '教师：$sanitizedTeacher',
      if (className != null && className.isNotEmpty) '班级：$className',
      if (campus != null && campus.isNotEmpty) '校区：$campus',
      ...extraLines,
    ];

    return CalendarImportMetadata.buildDescription(
      semesterId: semesterId,
      importKey: importKey,
      detailLines: detailLines,
    );
```

Update `_buildDescription` parameters to include:

```dart
    required String semesterId,
```

For graduate mapping, pass the current `semesterId` so graduate imports also get the new marker even though graduate semester switching is out of scope.

- [ ] **Step 6: Run service and metadata tests**

Run:

```powershell
flutter test test/nju_schedule_service_undergrad_test.dart test/calendar_import_metadata_test.dart
```

Expected: PASS.

- [ ] **Step 7: Run all current tests**

Run:

```powershell
flutter test
```

Expected: PASS. If widget smoke fails because `ScheduleBundle` construction changed, update the affected fake/test bundle to include `semesterId`, `semesterStart`, and `semesterEnd`.

- [ ] **Step 8: Commit Task 4**

```powershell
git add lib/services/nju_schedule_service.dart test/nju_schedule_service_undergrad_test.dart
git commit -m "feat: fetch selected undergrad semester schedule"
```

## Task 5: Main Page Semester Selection Flow

**Files:**
- Modify: `lib/main.dart`
- Modify: `test/widget_test.dart`

- [ ] **Step 1: Write failing widget tests for logged-in semester UI**

Modify `test/widget_test.dart`:

```dart
import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nju_calendar_importer_flutter/main.dart';
import 'package:nju_calendar_importer_flutter/models/login_models.dart';
import 'package:nju_calendar_importer_flutter/models/nju_course.dart';
import 'package:nju_calendar_importer_flutter/models/school_type.dart';
import 'package:nju_calendar_importer_flutter/models/nju_semester.dart';
import 'package:nju_calendar_importer_flutter/services/auth_service.dart';
import 'package:nju_calendar_importer_flutter/services/calendar_sync_service.dart';
import 'package:nju_calendar_importer_flutter/services/nju_schedule_service.dart';
import 'package:nju_calendar_importer_flutter/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WidgetFakeAuthService extends AuthService {
  WidgetFakeAuthService(this.session) : super(StorageService());

  final SessionInfo? session;

  @override
  Future<SessionInfo?> restoreSession() async => session;
}

class WidgetFakeScheduleService extends NjuScheduleService {
  WidgetFakeScheduleService(AuthService authService) : super(authService);

  bool fetchedSchedule = false;

  @override
  Future<UndergradSemesterOptions> fetchUndergradSemesterOptions(
    SessionInfo session,
  ) async {
    return UndergradSemesterOptions(
      currentSemesterId: '2025-2026-2',
      currentSemesterName: '2025-2026学年 第2学期',
      semesters: [
        NjuSemester(
          id: '2025-2026-2',
          name: '2025-2026学年 第2学期',
          year: '2025-2026',
          term: '2',
          start: DateTime(2026, 3, 2),
          end: DateTime(2026, 7, 6).subtract(const Duration(milliseconds: 1)),
          isCurrent: true,
        ),
      ],
    );
  }

  @override
  Future<ScheduleBundle> fetchUndergradScheduleForSemester(
    SessionInfo session, {
    required String semesterId,
    required String semesterName,
    required DateTime semesterStart,
    required DateTime semesterEnd,
    bool includeFinalExams = true,
  }) async {
    fetchedSchedule = true;
    return ScheduleBundle(
      semesterId: semesterId,
      semesterName: semesterName,
      semesterStart: semesterStart,
      semesterEnd: semesterEnd,
      courseCount: 0,
      examCount: 0,
      events: const [],
    );
  }
}

class WidgetFakeCalendarSyncService extends CalendarSyncService {
  @override
  Future<List<Calendar>> listWritableCalendars() async => const [];
}

void main() {
  testWidgets('app bootstraps smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const NjuScheduleCalendarApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('logged in undergrad shows semester card without auto fetching schedule',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'privacy_policy_accepted_v1': true});
    const session = SessionInfo(
      username: 'student',
      schoolType: SchoolType.undergrad,
      cookiesByBaseUrl: {},
    );
    final auth = WidgetFakeAuthService(session);
    final schedule = WidgetFakeScheduleService(auth);

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          authService: auth,
          scheduleService: schedule,
          calendarSyncService: WidgetFakeCalendarSyncService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('课表学期'), findsOneWidget);
    expect(find.text('2025-2026学年 第2学期'), findsWidgets);
    expect(find.text('系统日历同步'), findsNothing);
    expect(find.text('删除本软件生成的日程'), findsOneWidget);
    expect(schedule.fetchedSchedule, isFalse);
  });
}
```

- [ ] **Step 2: Run widget tests and verify they fail**

Run:

```powershell
flutter test test/widget_test.dart
```

Expected: FAIL because `HomePage` does not accept injected services and no semester card exists.

- [ ] **Step 3: Add injectable services to `HomePage`**

Modify `HomePage` in `lib/main.dart`:

```dart
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.authService,
    this.scheduleService,
    this.calendarSyncService,
  });

  final AuthService? authService;
  final NjuScheduleService? scheduleService;
  final CalendarSyncService? calendarSyncService;

  @override
  State<HomePage> createState() => _HomePageState();
}
```

In `initState`, replace service creation with:

```dart
    _storageService = StorageService();
    _authService = widget.authService ?? AuthService(_storageService);
    _scheduleService = widget.scheduleService ?? NjuScheduleService(_authService);
    _calendarSyncService =
        widget.calendarSyncService ?? CalendarSyncService();
```

- [ ] **Step 4: Add semester state fields**

In `_HomePageState`, add:

```dart
  List<NjuSemester> _semesterOptions = const [];
  NjuSemester? _selectedSemester;
  bool _loadingSemesters = false;
  bool _semesterOptionsLoaded = false;
```

Add import:

```dart
import 'models/nju_semester.dart';
```

- [ ] **Step 5: Stop automatic schedule fetch and load semester options**

In `_bootstrap`, replace:

```dart
      await _loadSchedule();
```

with:

```dart
      if (savedSession.schoolType == SchoolType.undergrad) {
        await _loadSemesterOptions();
      }
```

In `_openWebLogin`, replace:

```dart
      await _loadSchedule();
```

with:

```dart
      if (session.schoolType == SchoolType.undergrad) {
        await _loadSemesterOptions();
      }
```

In `_logout`, also clear semester state:

```dart
      _semesterOptions = const [];
      _selectedSemester = null;
      _semesterOptionsLoaded = false;
```

- [ ] **Step 6: Add semester loading method**

Add this method in `_HomePageState`:

```dart
  Future<void> _loadSemesterOptions() async {
    if (_session == null || _session!.schoolType != SchoolType.undergrad) {
      return;
    }

    setState(() {
      _loadingSemesters = true;
      _semesterOptionsLoaded = false;
    });

    try {
      final result =
          await _scheduleService.fetchUndergradSemesterOptions(_session!);
      if (!mounted) return;

      setState(() {
        _semesterOptions = result.semesters;
        _selectedSemester = result.currentSemester;
        _semesterOptionsLoaded = true;
        _bundle = null;
      });

      if (_selectedSemester == null) {
        _showSnackBar('未找到可选择的本科教学学期。');
      } else if (_selectedSemester!.id != result.currentSemesterId) {
        _showSnackBar('未在列表中找到当前学期，已选择最新可用学期。');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _semesterOptions = const [];
        _selectedSemester = null;
        _semesterOptionsLoaded = false;
      });
      _showSnackBar('加载学期列表失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingSemesters = false;
        });
      }
    }
  }
```

- [ ] **Step 7: Replace `_loadSchedule` with selected-semester fetch**

Replace `_loadSchedule` with:

```dart
  Future<void> _loadSchedule() async {
    if (_session == null || _selectedSemester == null) return;

    setState(() {
      _loadingSchedule = true;
    });
    try {
      final semester = _selectedSemester!;
      final bundle = await _scheduleService.fetchUndergradScheduleForSemester(
        _session!,
        semesterId: semester.id,
        semesterName: semester.name,
        semesterStart: semester.start,
        semesterEnd: semester.end,
        includeFinalExams: true,
      );
      if (!mounted) return;

      if (bundle.events.isEmpty) {
        setState(() {
          _bundle = null;
        });
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('暂无可导入日程'),
            content: Text('${semester.name} 暂无可导入课程或考试日程。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
        return;
      }

      setState(() {
        _bundle = bundle;
      });
      _showSnackBar('已获取 ${bundle.events.length} 条日历事件。');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('获取课表失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingSchedule = false;
        });
      }
    }
  }
```

- [ ] **Step 8: Add semester card UI**

Add `_buildSemesterCard`:

```dart
  Widget _buildSemesterCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '课表学期',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (_loadingSemesters && !_semesterOptionsLoaded)
              const LinearProgressIndicator()
            else ...[
              DropdownButtonFormField<NjuSemester>(
                initialValue: _selectedSemester,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '选择学期',
                  border: OutlineInputBorder(),
                ),
                items: _semesterOptions
                    .map(
                      (semester) => DropdownMenuItem(
                        value: semester,
                        child: Text(semester.name),
                      ),
                    )
                    .toList(),
                onChanged: (_loadingSchedule || _semesterOptions.isEmpty)
                    ? null
                    : (value) {
                        setState(() {
                          _selectedSemester = value;
                          _bundle = null;
                        });
                      },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (_loadingSchedule || _selectedSemester == null)
                          ? null
                          : _loadSchedule,
                      icon: _loadingSchedule
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download),
                      label: const Text('拉取所选学期课表'),
                    ),
                  ),
                ],
              ),
              if (!_semesterOptionsLoaded && !_loadingSemesters) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loadSemesterOptions,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新加载学期列表'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 9: Wire card order in `build`**

In the main `ListView` children, use this order:

```dart
                      if (_session == null)
                        _buildLoginCard()
                      else ...[
                        _buildSessionCard(),
                        if (_session!.schoolType == SchoolType.undergrad) ...[
                          const SizedBox(height: 12),
                          _buildSemesterCard(),
                        ],
                      ],
                      if (_bundle != null) ...[
                        const SizedBox(height: 12),
                        _buildCalendarCard(),
                      ],
                      const SizedBox(height: 12),
                      _buildGeneratedEventsCleanupCard(),
```

For this task, make `_buildGeneratedEventsCleanupCard` a simple card that navigates nowhere yet:

```dart
  Widget _buildGeneratedEventsCleanupCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '删除本软件生成的日程',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.delete_sweep),
              label: const Text('扫描并删除导入日程'),
            ),
          ],
        ),
      ),
    );
  }
```

Task 6 will connect the button to the cleanup page.

- [ ] **Step 10: Run widget tests**

Run:

```powershell
flutter test test/widget_test.dart
```

Expected: PASS.

- [ ] **Step 11: Commit Task 5**

```powershell
git add lib/main.dart test/widget_test.dart
git commit -m "feat: add undergrad semester selection UI"
```

## Task 6: Independent Generated Events Cleanup Page

**Files:**
- Create: `lib/pages/generated_events_cleanup_page.dart`
- Modify: `lib/services/calendar_sync_service.dart`
- Modify: `lib/main.dart`
- Create: `test/generated_events_cleanup_page_test.dart`

- [ ] **Step 1: Write failing cleanup page widget test**

Create `test/generated_events_cleanup_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nju_calendar_importer_flutter/pages/generated_events_cleanup_page.dart';
import 'package:nju_calendar_importer_flutter/services/calendar_import_metadata.dart';
import 'package:nju_calendar_importer_flutter/services/calendar_sync_service.dart';

class CleanupFakeCalendarSyncService extends CalendarSyncService {
  CleanupFakeCalendarSyncService(this.groups);

  final List<GeneratedEventsGroup> groups;
  final deletedGroups = <String>[];
  var deletedAll = false;

  @override
  Future<List<GeneratedEventsGroup>> scanGeneratedEventGroups() async => groups;

  @override
  Future<int> deleteGeneratedEventGroup(GeneratedEventsGroup group) async {
    deletedGroups.add(group.label);
    return group.count;
  }

  @override
  Future<int> deleteGeneratedEventGroups(
    List<GeneratedEventsGroup> groupsToDelete,
  ) async {
    deletedAll = true;
    return groupsToDelete.fold<int>(0, (sum, group) => sum + group.count);
  }
}

void main() {
  testWidgets('cleanup page lists semester groups and supports deleting one group',
      (tester) async {
    final service = CleanupFakeCalendarSyncService([
      GeneratedEventsGroup(
        semesterId: '2025-2026-2',
        label: '2025-2026-2',
        events: const [
          ImportedCalendarEvent(
            deleteId: '1',
            calendarId: 'cal',
            calendarName: 'Personal',
            description: '[NJU_CALENDAR_IMPORTER]\nsemester_id=2025-2026-2',
          ),
        ],
      ),
      GeneratedEventsGroup(
        semesterId: null,
        label: '旧版本导入（未记录学期）',
        events: const [
          ImportedCalendarEvent(
            deleteId: '2',
            calendarId: 'cal',
            calendarName: 'Personal',
            description: '[NJU_SCHEDULE_IMPORT]',
          ),
        ],
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: GeneratedEventsCleanupPage(calendarSyncService: service),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2025-2026-2'), findsOneWidget);
    expect(find.text('旧版本导入（未记录学期）'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '删除').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认删除'));
    await tester.pumpAndSettle();

    expect(service.deletedGroups, contains('2025-2026-2'));
  });
}
```

- [ ] **Step 2: Run cleanup page test and verify it fails**

Run:

```powershell
flutter test test/generated_events_cleanup_page_test.dart
```

Expected: FAIL because `GeneratedEventsCleanupPage` and scan/delete service methods do not exist.

- [ ] **Step 3: Add scan/delete service methods**

In `lib/services/calendar_sync_service.dart`, add:

```dart
  Future<List<GeneratedEventsGroup>> scanGeneratedEventGroups() async {
    final permission = await _ensurePermissions();
    if (permission != CalendarPermissionStatus.granted) {
      throw Exception('当前权限只能写入，无法读取已有事件；请在系统设置中授予完整日历权限后再试。');
    }

    final calendars = await DeviceCalendar.instance.listCalendars();
    final now = DateTime.now();
    final importedEvents = <ImportedCalendarEvent>[];

    for (final calendar in calendars) {
      for (int i = -5; i <= 5; i++) {
        final year = now.year + i;
        final rangeStart = DateTime(year, 1, 1);
        final rangeEnd = DateTime(year, 12, 31, 23, 59, 59);
        final events = await DeviceCalendar.instance.listEvents(
          rangeStart,
          rangeEnd,
          calendarIds: [calendar.id],
        );

        for (final event in events) {
          final metadata = CalendarImportMetadata.parse(event.description);
          if (!metadata.isGeneratedByApp) continue;

          var deleteId = event.eventId;
          if (deleteId.isEmpty) {
            deleteId = event.instanceId;
          }
          if (deleteId.isEmpty) continue;

          importedEvents.add(
            ImportedCalendarEvent(
              deleteId: deleteId,
              calendarId: calendar.id,
              calendarName: calendar.name,
              description: event.description,
            ),
          );
        }
      }
    }

    return CalendarImportMetadata.groupGeneratedEvents(importedEvents);
  }

  Future<int> deleteGeneratedEventGroup(GeneratedEventsGroup group) async {
    return deleteGeneratedEventGroups([group]);
  }

  Future<int> deleteGeneratedEventGroups(
    List<GeneratedEventsGroup> groups,
  ) async {
    final permission = await _ensurePermissions();
    if (permission != CalendarPermissionStatus.granted) {
      throw Exception('当前权限只能写入，无法读取已有事件；请在系统设置中授予完整日历权限后再试。');
    }

    var deleted = 0;
    for (final group in groups) {
      for (final event in group.events) {
        try {
          await DeviceCalendar.instance.deleteEvent(eventId: event.deleteId);
          deleted += 1;
        } catch (_) {
          // Ignore a single delete failure so the rest of the cleanup can continue.
        }
      }
    }
    return deleted;
  }
```

- [ ] **Step 4: Create cleanup page**

Create `lib/pages/generated_events_cleanup_page.dart`:

```dart
import 'package:flutter/material.dart';

import '../services/calendar_import_metadata.dart';
import '../services/calendar_sync_service.dart';

class GeneratedEventsCleanupPage extends StatefulWidget {
  const GeneratedEventsCleanupPage({
    super.key,
    required this.calendarSyncService,
  });

  final CalendarSyncService calendarSyncService;

  @override
  State<GeneratedEventsCleanupPage> createState() =>
      _GeneratedEventsCleanupPageState();
}

class _GeneratedEventsCleanupPageState
    extends State<GeneratedEventsCleanupPage> {
  var _loading = true;
  var _deleting = false;
  String? _error;
  List<GeneratedEventsGroup> _groups = const [];

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final groups = await widget.calendarSyncService.scanGeneratedEventGroups();
      if (!mounted) return;
      setState(() {
        _groups = groups;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _groups = const [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _deleteGroup(GeneratedEventsGroup group) async {
    final confirmed = await _confirm(
      title: '确认删除',
      message: '将删除 ${group.label} 中的 ${group.count} 条本软件生成日程。',
    );
    if (!confirmed) return;

    await _deleteGroups([group]);
  }

  Future<void> _deleteAll() async {
    final total = _groups.fold<int>(0, (sum, group) => sum + group.count);
    final confirmed = await _confirm(
      title: '确认全部删除',
      message: '将删除扫描到的全部 $total 条本软件生成日程。',
    );
    if (!confirmed) return;

    await _deleteGroups(_groups);
  }

  Future<void> _deleteGroups(List<GeneratedEventsGroup> groups) async {
    setState(() {
      _deleting = true;
    });
    try {
      final deleted =
          await widget.calendarSyncService.deleteGeneratedEventGroups(groups);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除 $deleted 条本软件生成日程。')),
      );
      await _scan();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _deleting = false;
        });
      }
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('确认删除'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('删除本软件生成的日程')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildError()
                : _buildGroups(),
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_error!),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _scan,
            icon: const Icon(Icons.refresh),
            label: const Text('重新扫描'),
          ),
        ],
      ),
    );
  }

  Widget _buildGroups() {
    if (_groups.isEmpty) {
      return RefreshIndicator(
        onRefresh: _scan,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            SizedBox(height: 120),
            Center(child: Text('没有扫描到本软件生成的日程。')),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final group in _groups) ...[
          Card(
            child: ListTile(
              title: Text(group.label),
              subtitle: Text('${group.count} 条日程'),
              trailing: OutlinedButton(
                onPressed: _deleting ? null : () => _deleteGroup(group),
                child: const Text('删除'),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _deleting ? null : _deleteAll,
          icon: _deleting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_forever),
          label: const Text('全部删除'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Wire cleanup card button**

In `lib/main.dart`, import:

```dart
import 'pages/generated_events_cleanup_page.dart';
```

Replace the disabled `OutlinedButton.icon` in `_buildGeneratedEventsCleanupCard` with:

```dart
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GeneratedEventsCleanupPage(
                      calendarSyncService: _calendarSyncService,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.delete_sweep),
              label: const Text('扫描并删除导入日程'),
            ),
```

- [ ] **Step 6: Run cleanup tests**

Run:

```powershell
flutter test test/generated_events_cleanup_page_test.dart test/calendar_import_metadata_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit Task 6**

```powershell
git add lib/pages/generated_events_cleanup_page.dart lib/services/calendar_sync_service.dart lib/main.dart test/generated_events_cleanup_page_test.dart
git commit -m "feat: add generated calendar event cleanup page"
```

## Task 7: Final Integration Verification

**Files:**
- Read: files changed in Tasks 1-6

- [ ] **Step 1: Run analyzer**

Run:

```powershell
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 2: Run all tests**

Run:

```powershell
flutter test
```

Expected: all tests PASS.

- [ ] **Step 3: Manual sanity check app starts**

Run:

```powershell
flutter run -d windows
```

Expected:

- App launches.
- Logged-out state shows login card and bottom “删除本软件生成的日程” card.
- After login or restored本科 session, app shows “课表学期” card and does not auto-fetch schedule.
- “系统日历同步” card appears only after a selected-semester fetch returns events.

Stop the app with `q` in the terminal.

- [ ] **Step 4: Inspect git diff**

Run:

```powershell
git status --short
git diff --stat
```

Expected: `git status --short` is empty after the task commits above. If it prints files, inspect the listed paths and return to the task that owns those files.

- [ ] **Step 5: Confirm no integration-only diff remains**

Run:

```powershell
git status --short
```

Expected: no output. If there is output, do not create a broad integration commit; return to the relevant earlier task, fix it there, rerun Task 7, and commit with that task's message pattern.

## Self-Review

Spec coverage:

- 本科-only scope: Task 4 only adds本科 selected-semester APIs; graduate switching is not added.
- Official semester list and current default: Task 1 and Task 4 cover `cxjcs.do` and `dqxnxq.do`.
- No auto-fetch after login: Task 5 changes `_bootstrap` and `_openWebLogin`.
- Dropdown plus fetch button: Task 5 adds `_buildSemesterCard`.
- Empty selected semester behavior: Task 5 `_loadSchedule` dialog clears `_bundle`.
- New marker and old marker compatibility: Task 2 and Task 3 add `[NJU_CALENDAR_IMPORTER]` and recognize `[NJU_SCHEDULE_IMPORT]`.
- Semester-bound overwrite deletion: Task 3 uses `bundle.semesterStart`, `bundle.semesterEnd`, and `semesterId`.
- Independent bottom cleanup card: Task 5 creates always-visible bottom card, Task 6 wires it.
- Scan by `semester_id`, selective delete, and all delete: Task 2 grouping helpers and Task 6 cleanup page/service implement this.

Placeholder scan:

- The plan contains no unresolved blanks, no vague implementation instruction, and no unnamed test command.

Type consistency:

- `NjuSemester`, `UndergradSemesterOptions`, `CalendarImportMetadata`, `ImportedCalendarEvent`, and `GeneratedEventsGroup` names are defined before later tasks use them.
