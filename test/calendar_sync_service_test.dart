import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nju_calendar_importer_flutter/models/nju_course.dart';
import 'package:nju_calendar_importer_flutter/services/calendar_import_metadata.dart';
import 'package:nju_calendar_importer_flutter/services/calendar_sync_service.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class CalendarSyncFakePlatform extends DeviceCalendarPlusPlatform
    with MockPlatformInterfaceMixin {
  CalendarSyncFakePlatform({
    this.permission = CalendarPermissionStatus.granted,
  });

  CalendarPermissionStatus permission;
  final deletedEventIds = <String>[];
  final listEventCalls =
      <({DateTime start, DateTime end, List<String>? calendarIds})>[];
  List<Map<String, dynamic>> calendars = const [];
  List<Map<String, dynamic>> events = const [];

  @override
  Future<String?> hasPermissions() async => permission.name;

  @override
  Future<String?> requestPermissions() async => permission.name;

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<List<Map<String, dynamic>>> listCalendars() async => calendars;

  @override
  Future<List<Map<String, dynamic>>> listSources() async => [];

  @override
  Future<String> createCalendar(
    String name,
    String? colorHex,
    CreateCalendarPlatformOptions? platformOptions,
  ) async =>
      'calendar-id';

  @override
  Future<void> updateCalendar(
    String calendarId,
    String? name,
    String? colorHex,
  ) async {}

  @override
  Future<void> deleteCalendar(String calendarId) async {}

  @override
  Future<List<Map<String, dynamic>>> listEvents(
    DateTime startDate,
    DateTime endDate,
    List<String>? calendarIds,
  ) async {
    listEventCalls.add((
      start: startDate,
      end: endDate,
      calendarIds: calendarIds,
    ));
    return events.where((event) {
      final eventStart = DateTime.fromMillisecondsSinceEpoch(
        event['startDate'] as int,
      );
      final eventCalendarId = event['calendarId'] as String?;
      final inCalendar =
          calendarIds == null || calendarIds.contains(eventCalendarId);
      return inCalendar &&
          !eventStart.isBefore(startDate) &&
          !eventStart.isAfter(endDate);
    }).toList();
  }

  @override
  Future<Map<String, dynamic>?> getEvent(
          String eventId, int? timestamp) async =>
      null;

  @override
  Future<void> showEventModal(String eventId, int? timestamp) async {}

  @override
  Future<String> createEvent(
    String calendarId,
    String title,
    DateTime startDate,
    DateTime endDate,
    bool isAllDay,
    String? description,
    String? location,
    String? url,
    String? timeZone,
    String availability,
    String? recurrenceRule,
  ) async =>
      'created';

  @override
  Future<void> deleteEvent(String eventId) async {
    deletedEventIds.add(eventId);
  }

  @override
  Future<void> updateEvent(
    String eventId, {
    String? title,
    DateTime? startDate,
    DateTime? endDate,
    String? description,
    String? location,
    bool? isAllDay,
    String? timeZone,
    String? availability,
  }) async {}

  @override
  Future<void> showCreateEventModal({
    String? title,
    int? startDate,
    int? endDate,
    String? description,
    String? location,
    bool? isAllDay,
    String? recurrenceRule,
    String? availability,
  }) async {}
}

Map<String, dynamic> importedCalendarEvent({
  required String id,
  required String description,
  String calendarId = 'target-calendar',
  DateTime? start,
}) {
  final startDate = start ?? DateTime(2026, 3, 3);
  return {
    'eventId': id,
    'instanceId': id,
    'calendarId': calendarId,
    'title': 'Old import',
    'description': description,
    'startDate': startDate.millisecondsSinceEpoch,
    'endDate': startDate.add(const Duration(hours: 1)).millisecondsSinceEpoch,
    'isAllDay': false,
    'availability': 'busy',
    'status': 'confirmed',
    'isRecurring': false,
  };
}

void main() {
  late CalendarSyncFakePlatform fakePlatform;

  setUp(() {
    fakePlatform = CalendarSyncFakePlatform();
    DeviceCalendarPlusPlatform.instance = fakePlatform;
  });

  test('overwrite range uses official semester boundaries when present', () {
    final bundle = ScheduleBundle(
      semesterId: '2025-2026-2',
      semesterName: '2025-2026学年 第2学期',
      semesterStart: DateTime(2026, 3, 2),
      semesterEnd:
          DateTime(2026, 7, 6).subtract(const Duration(milliseconds: 1)),
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
    expect(range.end,
        DateTime(2026, 7, 6).subtract(const Duration(milliseconds: 1)));
  });

  test('empty bundle still uses semester boundaries for overwrite range', () {
    final bundle = ScheduleBundle(
      semesterId: '2025-2026-2',
      semesterName: '2025-2026学年 第2学期',
      semesterStart: DateTime(2026, 3, 2),
      semesterEnd:
          DateTime(2026, 7, 6).subtract(const Duration(milliseconds: 1)),
      courseCount: 0,
      examCount: 0,
      events: const [],
    );

    final range = CalendarSyncService.overwriteRangeFor(bundle);

    expect(range.start, DateTime(2026, 3, 2));
    expect(range.end,
        DateTime(2026, 7, 6).subtract(const Duration(milliseconds: 1)));
  });

  test(
      'legacy fallback range expands fetched schedule to week Monday through Sunday',
      () {
    final bundle = ScheduleBundle(
      semesterId: '2025-2026-2',
      semesterName: '2025-2026学年 第2学期',
      semesterStart: DateTime(1900),
      semesterEnd: DateTime(1900),
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

  test('empty bundle overwrite deletes stale same-semester generated events',
      () async {
    final bundle = ScheduleBundle(
      semesterId: '2025-2026-2',
      semesterName: '2025-2026学年 第2学期',
      semesterStart: DateTime(2026, 3, 2),
      semesterEnd:
          DateTime(2026, 7, 6).subtract(const Duration(milliseconds: 1)),
      courseCount: 0,
      examCount: 0,
      events: const [],
    );
    fakePlatform.events = [
      importedCalendarEvent(
        id: 'same-semester',
        description: '[NJU_CALENDAR_IMPORTER]\nsemester_id=2025-2026-2',
        start: DateTime(2026, 3, 3),
      ),
      importedCalendarEvent(
        id: 'other-semester',
        description: '[NJU_CALENDAR_IMPORTER]\nsemester_id=2025-2026-1',
        start: DateTime(2026, 3, 3),
      ),
      importedCalendarEvent(
        id: 'manual',
        description: 'manual event',
        start: DateTime(2026, 3, 3),
      ),
    ];

    final result = await CalendarSyncService().syncEvents(
      calendarId: 'target-calendar',
      bundle: bundle,
      overwritePreviousImports: true,
    );

    expect(result.created, 0);
    expect(result.deleted, 1);
    expect(fakePlatform.deletedEventIds, ['same-semester']);
    expect(fakePlatform.listEventCalls.single.start, DateTime(2026, 3, 2));
    expect(
      fakePlatform.listEventCalls.single.end,
      DateTime(2026, 7, 6).subtract(const Duration(milliseconds: 1)),
    );
    expect(fakePlatform.listEventCalls.single.calendarIds, ['target-calendar']);
  });

  test('deleteImportedEvents deletes current and legacy generated events',
      () async {
    final currentYear = DateTime.now().year;
    fakePlatform.events = [
      importedCalendarEvent(
        id: 'current-marker',
        description: '[NJU_CALENDAR_IMPORTER]\nsemester_id=2025-2026-2',
        start: DateTime(currentYear, 3, 3),
      ),
      importedCalendarEvent(
        id: 'legacy-marker',
        description: '[NJU_SCHEDULE_IMPORT]\nimport_key=old',
        start: DateTime(currentYear, 3, 4),
      ),
      importedCalendarEvent(
        id: 'manual',
        description: 'manual event',
        start: DateTime(currentYear, 3, 5),
      ),
    ];

    final deleted = await CalendarSyncService().deleteImportedEvents(
      calendarId: 'target-calendar',
    );

    expect(deleted, 2);
    expect(fakePlatform.deletedEventIds, [
      'current-marker',
      'legacy-marker',
    ]);
  });

  test('scanGeneratedEventGroups groups generated events across calendars',
      () async {
    final currentYear = DateTime.now().year;
    fakePlatform.calendars = [
      {
        'id': 'personal',
        'name': 'Personal',
        'readOnly': false,
      },
      {
        'id': 'work',
        'name': 'Work',
        'readOnly': false,
      },
    ];
    fakePlatform.events = [
      importedCalendarEvent(
        id: 'current-marker',
        calendarId: 'personal',
        description: '[NJU_CALENDAR_IMPORTER]\nsemester_id=2025-2026-2',
        start: DateTime(currentYear, 3, 3),
      ),
      importedCalendarEvent(
        id: 'legacy-marker',
        calendarId: 'work',
        description: '[NJU_SCHEDULE_IMPORT]\nimport_key=old',
        start: DateTime(currentYear, 4, 4),
      ),
      importedCalendarEvent(
        id: 'manual',
        calendarId: 'personal',
        description: 'manual event',
        start: DateTime(currentYear, 5, 5),
      ),
    ];

    final groups = await CalendarSyncService().scanGeneratedEventGroups();

    expect(groups.map((group) => group.label), [
      '2025-2026-2',
      CalendarImportMetadata.legacyGroupLabel,
    ]);
    expect(groups.first.events.single.deleteId, 'current-marker');
    expect(groups.first.events.single.calendarName, 'Personal');
    expect(groups.last.events.single.deleteId, 'legacy-marker');
    expect(groups.last.events.single.calendarName, 'Work');
  });

  test('deleteGeneratedEventGroups deletes every event in selected groups',
      () async {
    final deleted = await CalendarSyncService().deleteGeneratedEventGroups([
      GeneratedEventsGroup(
        semesterId: '2025-2026-2',
        label: '2025-2026-2',
        events: const [
          ImportedCalendarEvent(
            deleteId: 'current-marker',
            calendarId: 'personal',
            calendarName: 'Personal',
            description: '[NJU_CALENDAR_IMPORTER]\nsemester_id=2025-2026-2',
          ),
        ],
      ),
      GeneratedEventsGroup(
        semesterId: null,
        label: CalendarImportMetadata.legacyGroupLabel,
        events: const [
          ImportedCalendarEvent(
            deleteId: 'legacy-marker',
            calendarId: 'work',
            calendarName: 'Work',
            description: '[NJU_SCHEDULE_IMPORT]',
          ),
        ],
      ),
    ]);

    expect(deleted, 2);
    expect(fakePlatform.deletedEventIds, [
      'current-marker',
      'legacy-marker',
    ]);
  });
}
