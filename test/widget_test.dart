import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nju_calendar_importer_flutter/main.dart';
import 'package:nju_calendar_importer_flutter/models/login_models.dart';
import 'package:nju_calendar_importer_flutter/models/nju_course.dart';
import 'package:nju_calendar_importer_flutter/models/nju_semester.dart';
import 'package:nju_calendar_importer_flutter/models/school_type.dart';
import 'package:nju_calendar_importer_flutter/services/auth_service.dart';
import 'package:nju_calendar_importer_flutter/services/calendar_sync_service.dart';
import 'package:nju_calendar_importer_flutter/services/nju_schedule_service.dart';
import 'package:nju_calendar_importer_flutter/services/storage_service.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WidgetFakeCalendarPlatform extends DeviceCalendarPlusPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> hasPermissions() async =>
      CalendarPermissionStatus.granted.name;

  @override
  Future<String?> requestPermissions() async =>
      CalendarPermissionStatus.granted.name;

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<List<Map<String, dynamic>>> listCalendars() async => [];

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
  ) async =>
      [];

  @override
  Future<Map<String, dynamic>?> getEvent(
    String eventId,
    int? timestamp,
  ) async =>
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
  Future<void> deleteEvent(String eventId) async {}

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

class WidgetFakeAuthService extends AuthService {
  WidgetFakeAuthService({this.restoredSession}) : super(StorageService());

  final SessionInfo? restoredSession;

  @override
  Future<SessionInfo?> restoreSession() async => restoredSession;

  @override
  Future<void> clearSession() async {}

  @override
  Future<void> clearWebViewCookies() async {}
}

class WidgetFakeScheduleService extends NjuScheduleService {
  WidgetFakeScheduleService({
    required this.options,
    ScheduleBundle? bundle,
  })  : bundle = bundle ?? _bundleFor(options.currentSemester!),
        super(WidgetFakeAuthService());

  final UndergradSemesterOptions options;
  final ScheduleBundle bundle;
  var fetchedOptions = false;
  var fetchedSchedule = false;
  String? requestedSemesterId;

  @override
  Future<UndergradSemesterOptions> fetchUndergradSemesterOptions(
    SessionInfo session,
  ) async {
    fetchedOptions = true;
    return options;
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
    requestedSemesterId = semesterId;
    return bundle;
  }
}

class WidgetFakeCalendarSyncService extends CalendarSyncService {}

SessionInfo _undergradSession() {
  return const SessionInfo(
    username: 'student',
    schoolType: SchoolType.undergrad,
    cookiesByBaseUrl: {},
  );
}

NjuSemester _semester({
  required String id,
  required String name,
  required bool isCurrent,
}) {
  return NjuSemester(
    id: id,
    name: name,
    year: '2025-2026',
    term: id.endsWith('-1') ? '1' : '2',
    start: DateTime(2026, 2, 23),
    end: DateTime(2026, 7, 5, 23, 59, 59, 999),
    isCurrent: isCurrent,
  );
}

UndergradSemesterOptions _semesterOptions() {
  final current = _semester(
    id: '2025-2026-2',
    name: '2025-2026学年 第2学期',
    isCurrent: true,
  );
  return UndergradSemesterOptions(
    currentSemesterId: current.id,
    currentSemesterName: current.name,
    semesters: [
      current,
      _semester(
        id: '2025-2026-1',
        name: '2025-2026学年 第1学期',
        isCurrent: false,
      ),
    ],
  );
}

ScheduleBundle _bundleFor(NjuSemester semester) {
  return ScheduleBundle(
    semesterId: semester.id,
    semesterName: semester.name,
    semesterStart: semester.start,
    semesterEnd: semester.end,
    events: [
      NjuCourseEvent(
        title: '软件工程',
        start: DateTime(2026, 3, 2, 8),
        end: DateTime(2026, 3, 2, 9, 40),
        location: '仙林',
        description: '课程',
        importKey: 'course-1',
      ),
    ],
    courseCount: 1,
    examCount: 0,
  );
}

ScheduleBundle _emptyBundleFor(NjuSemester semester) {
  return ScheduleBundle(
    semesterId: semester.id,
    semesterName: semester.name,
    semesterStart: semester.start,
    semesterEnd: semester.end,
    events: const [],
    courseCount: 0,
    examCount: 0,
  );
}

void main() {
  setUp(() {
    DeviceCalendarPlusPlatform.instance = WidgetFakeCalendarPlatform();
  });

  testWidgets('app bootstraps smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const NjuScheduleCalendarApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets(
    'restored undergrad session shows semester picker before fetching schedule',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'privacy_policy_accepted_v1': true,
      });
      final options = _semesterOptions();
      final scheduleService = WidgetFakeScheduleService(options: options);

      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            authService: WidgetFakeAuthService(
              restoredSession: _undergradSession(),
            ),
            scheduleService: scheduleService,
            calendarSyncService: WidgetFakeCalendarSyncService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(scheduleService.fetchedOptions, isTrue);
      expect(scheduleService.fetchedSchedule, isFalse);
      expect(find.text('课表学期'), findsOneWidget);
      expect(find.text('2025-2026学年 第2学期'), findsOneWidget);
      expect(find.text('拉取所选学期课表'), findsOneWidget);
      expect(find.text('系统日历同步'), findsNothing);

      final cleanupButton = find.widgetWithText(OutlinedButton, '删除本软件生成的日程');
      expect(cleanupButton, findsOneWidget);
      expect(tester.widget<OutlinedButton>(cleanupButton).onPressed, isNull);
    },
  );

  testWidgets(
    'fetching selected undergrad semester reveals calendar sync controls',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'privacy_policy_accepted_v1': true,
      });
      final options = _semesterOptions();
      final scheduleService = WidgetFakeScheduleService(options: options);

      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            authService: WidgetFakeAuthService(
              restoredSession: _undergradSession(),
            ),
            scheduleService: scheduleService,
            calendarSyncService: WidgetFakeCalendarSyncService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('拉取所选学期课表'));
      await tester.pumpAndSettle();

      expect(scheduleService.fetchedSchedule, isTrue);
      expect(scheduleService.requestedSemesterId, '2025-2026-2');
      expect(find.text('系统日历同步'), findsOneWidget);
    },
  );

  testWidgets(
    'empty selected undergrad semester shows dialog without sync controls',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'privacy_policy_accepted_v1': true,
      });
      final options = _semesterOptions();
      final scheduleService = WidgetFakeScheduleService(
        options: options,
        bundle: _emptyBundleFor(options.currentSemester!),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            authService: WidgetFakeAuthService(
              restoredSession: _undergradSession(),
            ),
            scheduleService: scheduleService,
            calendarSyncService: WidgetFakeCalendarSyncService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('拉取所选学期课表'));
      await tester.pumpAndSettle();

      expect(find.text('未查询到课表'), findsOneWidget);
      expect(find.text('系统日历同步'), findsNothing);
    },
  );
}
