import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nju_calendar_importer_flutter/app_snack_bar.dart';
import 'package:nju_calendar_importer_flutter/main.dart';
import 'package:nju_calendar_importer_flutter/models/login_models.dart';
import 'package:nju_calendar_importer_flutter/models/nju_course.dart';
import 'package:nju_calendar_importer_flutter/models/nju_semester.dart';
import 'package:nju_calendar_importer_flutter/models/school_type.dart';
import 'package:nju_calendar_importer_flutter/pages/web_login_page.dart';
import 'package:nju_calendar_importer_flutter/services/auth_service.dart';
import 'package:nju_calendar_importer_flutter/services/calendar_sync_service.dart';
import 'package:nju_calendar_importer_flutter/services/nju_schedule_service.dart';
import 'package:nju_calendar_importer_flutter/services/settings_service.dart';
import 'package:nju_calendar_importer_flutter/services/storage_service.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class WidgetFakeCalendarPlatform extends DeviceCalendarPlusPlatform
    with MockPlatformInterfaceMixin {
  WidgetFakeCalendarPlatform({
    this.permissionStatus = CalendarPermissionStatus.granted,
    this.requestedPermissionStatus = CalendarPermissionStatus.granted,
  });

  final CalendarPermissionStatus permissionStatus;
  final CalendarPermissionStatus requestedPermissionStatus;
  var permissionCheckCalls = 0;
  var permissionRequestCalls = 0;
  final createdCalendarNames = <String>[];

  @override
  Future<String?> hasPermissions() async {
    permissionCheckCalls += 1;
    return permissionStatus.name;
  }

  @override
  Future<String?> requestPermissions() async {
    permissionRequestCalls += 1;
    return requestedPermissionStatus.name;
  }

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
  ) async {
    createdCalendarNames.add(name);
    return 'calendar-id';
  }

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
  var clearSessionCalls = 0;
  var clearWebViewCookiesCalls = 0;

  @override
  Future<SessionInfo?> restoreSession() async => restoredSession;

  @override
  Future<void> clearSession() async {
    clearSessionCalls += 1;
  }

  @override
  Future<void> clearWebViewCookies() async {
    clearWebViewCookiesCalls += 1;
  }
}

class WidgetFakeSettingsService extends SettingsService {
  WidgetFakeSettingsService(this.settings);

  AutoLoginSettings settings;

  @override
  Future<AutoLoginSettings> loadAll() async => settings;

  @override
  Future<void> saveAll(AutoLoginSettings settings) async {
    this.settings = settings;
  }
}

class WidgetFakeScheduleService extends NjuScheduleService {
  WidgetFakeScheduleService({
    required this.options,
    ScheduleBundle? bundle,
    ScheduleBundle? currentBundle,
    this.optionFetchFailures = 0,
    this.scheduleError,
  })  : bundle = bundle ?? _bundleFor(options.currentSemester!),
        currentBundle =
            currentBundle ?? bundle ?? _bundleFor(options.currentSemester!),
        super(WidgetFakeAuthService());

  final UndergradSemesterOptions options;
  final ScheduleBundle bundle;
  final ScheduleBundle currentBundle;
  final int optionFetchFailures;
  final Object? scheduleError;
  var optionFetchCalls = 0;
  var fetchedOptions = false;
  var fetchedSchedule = false;
  var fetchedCurrentSchedule = false;
  var scheduleFetchCalls = 0;
  String? requestedSemesterId;
  String? requestedSemesterName;
  DateTime? requestedSemesterStart;
  DateTime? requestedSemesterEnd;
  bool? requestedIncludeFinalExams;

  @override
  Future<UndergradSemesterOptions> fetchUndergradSemesterOptions(
    SessionInfo session,
  ) async {
    optionFetchCalls += 1;
    fetchedOptions = true;
    if (optionFetchCalls <= optionFetchFailures) {
      throw Exception('expired session');
    }
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
    scheduleFetchCalls += 1;
    if (scheduleError case final error?) throw error;
    fetchedSchedule = true;
    requestedSemesterId = semesterId;
    requestedSemesterName = semesterName;
    requestedSemesterStart = semesterStart;
    requestedSemesterEnd = semesterEnd;
    requestedIncludeFinalExams = includeFinalExams;
    return bundle;
  }

  @override
  Future<ScheduleBundle> fetchCurrentSemesterSchedule(
    SessionInfo session, {
    bool includeFinalExams = true,
  }) async {
    scheduleFetchCalls += 1;
    if (scheduleError case final error?) throw error;
    fetchedCurrentSchedule = true;
    requestedIncludeFinalExams = includeFinalExams;
    return currentBundle;
  }
}

class WidgetFakeCalendarSyncService extends CalendarSyncService {
  WidgetFakeCalendarSyncService({
    this.calendars = const [
      Calendar(id: 'default-calendar', name: '个人日历', readOnly: false),
    ],
    this.deletedCount = 3,
    this.listError,
  });

  final List<Calendar> calendars;
  final int deletedCount;
  final Object? listError;
  var deleteCalls = 0;
  String? deletedCalendarId;
  ScheduleBundle? deletedBundle;

  var listWritableCalendarsCalls = 0;

  @override
  Future<List<Calendar>> listWritableCalendars() async {
    listWritableCalendarsCalls += 1;
    if (listError case final error?) throw error;
    return calendars;
  }

  @override
  Future<int> deleteGeneratedEventsForBundle({
    required String calendarId,
    required ScheduleBundle bundle,
  }) async {
    deleteCalls += 1;
    deletedCalendarId = calendarId;
    deletedBundle = bundle;
    return deletedCount;
  }
}

class WidgetFakeWebViewPlatform extends WebViewPlatform {
  WidgetFakePlatformNavigationDelegate? navigationDelegate;
  WidgetFakePlatformWebViewController? controller;

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return navigationDelegate = WidgetFakePlatformNavigationDelegate(params);
  }

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return controller = WidgetFakePlatformWebViewController(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return WidgetFakePlatformWebViewWidget(params);
  }
}

class WidgetFakePlatformNavigationDelegate extends PlatformNavigationDelegate {
  WidgetFakePlatformNavigationDelegate(super.params) : super.implementation();

  PageEventCallback? onPageFinished;

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {}

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {}

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {
    this.onPageFinished = onPageFinished;
  }

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {}

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {}
}

class WidgetFakePlatformWebViewController extends PlatformWebViewController {
  WidgetFakePlatformWebViewController(super.params) : super.implementation();

  final scripts = <String>[];
  JavaScriptChannelParams? javaScriptChannel;
  Object javaScriptResult = false;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {
    javaScriptChannel = javaScriptChannelParams;
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    scripts.add(javaScript);
  }

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async {
    scripts.add(javaScript);
    return javaScriptResult;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<void> loadRequest(LoadRequestParams params) async {}

  @override
  Future<void> reload() async {}
}

class WidgetFakePlatformWebViewWidget extends PlatformWebViewWidget {
  WidgetFakePlatformWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(key: Key('fake-webview'));
  }
}

SessionInfo _undergradSession() {
  return const SessionInfo(
    username: 'student',
    schoolType: SchoolType.undergrad,
    cookiesByBaseUrl: {},
  );
}

SessionInfo _graduateSession() {
  return const SessionInfo(
    username: 'student',
    schoolType: SchoolType.graduate,
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
      _semester(id: '2025-2026-1', name: '2025-2026学年 第1学期', isCurrent: false),
    ],
  );
}

UndergradSemesterOptions _semesterOptionsWithMissingCurrent() {
  final options = _semesterOptions();
  return UndergradSemesterOptions(
    currentSemesterId: '2024-2025-2',
    currentSemesterName: '2024-2025学年 第2学期',
    semesters: options.semesters,
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

Future<WebLoginPage> _startBackgroundLogin(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'privacy_policy_accepted_20260914': true,
  });
  WebViewPlatform.instance = WidgetFakeWebViewPlatform();

  await tester.pumpWidget(
    MaterialApp(
      home: HomePage(
        authService: WidgetFakeAuthService(),
        scheduleService: WidgetFakeScheduleService(options: _semesterOptions()),
        calendarSyncService: WidgetFakeCalendarSyncService(),
        settingsService: WidgetFakeSettingsService(
          const AutoLoginSettings(username: '123456789', password: 'password'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('登录'));
  await tester.pump();
  return tester.widget<WebLoginPage>(find.byType(WebLoginPage));
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

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
    expect(app.theme?.brightness, Brightness.light);
    expect(app.darkTheme?.brightness, Brightness.dark);
    expect(app.theme?.snackBarTheme.backgroundColor, Colors.black);
    expect(app.darkTheme?.snackBarTheme.backgroundColor, Colors.black);
  });

  testWidgets('previous privacy consent must accept the 20260914 policy', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'privacy_policy_accepted_v3': true,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          authService: WidgetFakeAuthService(),
          scheduleService: WidgetFakeScheduleService(
            options: _semesterOptions(),
          ),
          calendarSyncService: WidgetFakeCalendarSyncService(),
          settingsService: WidgetFakeSettingsService(
            const AutoLoginSettings(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('隐私政策与用户说明'), findsOneWidget);
    expect(find.textContaining('2026年9月14日更新了隐私政策'), findsOneWidget);

    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('privacy_policy_accepted_20260914'), isTrue);
  });

  testWidgets('new app log immediately replaces the current one', (
    WidgetTester tester,
  ) async {
    late BuildContext appContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            appContext = context;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );

    showAppSnackBar(appContext, '第一条日志');
    await tester.pump();
    expect(find.text('第一条日志'), findsOneWidget);

    showAppSnackBar(appContext, '第二条日志');
    await tester.pump();
    expect(find.text('第一条日志'), findsNothing);
    expect(find.text('第二条日志'), findsOneWidget);
  });

  testWidgets(
    'restored undergrad session shows semester picker before fetching schedule',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'privacy_policy_accepted_20260914': true,
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
      expect(find.text('课表学期'), findsNothing);
      expect(find.text('2025-2026学年 第2学期'), findsOneWidget);
      expect(find.text('拉取所选学期课表'), findsOneWidget);
      expect(find.text('系统日历同步'), findsNothing);
      expect(find.text('删除本软件生成的日程'), findsNothing);
      expect(find.text('扫描并删除导入日程'), findsNothing);
    },
  );

  testWidgets(
    'failed startup semester fetch automatically logs in and retries once',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'privacy_policy_accepted_20260914': true,
      });
      WebViewPlatform.instance = WidgetFakeWebViewPlatform();
      final authService = WidgetFakeAuthService(
        restoredSession: _undergradSession(),
      );
      final scheduleService = WidgetFakeScheduleService(
        options: _semesterOptions(),
        optionFetchFailures: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            authService: authService,
            scheduleService: scheduleService,
            calendarSyncService: WidgetFakeCalendarSyncService(),
            settingsService: WidgetFakeSettingsService(
              const AutoLoginSettings(
                username: '123456789',
                password: 'password',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 20 && authService.clearSessionCalls == 0; i++) {
        await tester.pump();
      }

      expect(scheduleService.optionFetchCalls, 1);
      expect(authService.clearSessionCalls, 1);
      expect(authService.clearWebViewCookiesCalls, 1);
      expect(find.byType(WebLoginPage), findsNothing);

      await tester.pump(const Duration(milliseconds: 499));
      expect(find.byType(WebLoginPage), findsNothing);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.byType(WebLoginPage), findsOneWidget);

      final backgroundPage = tester.widget<WebLoginPage>(
        find.byType(WebLoginPage),
      );
      backgroundPage.onSession!.call(_undergradSession());
      await tester.pumpAndSettle();

      expect(scheduleService.optionFetchCalls, 2);
      expect(find.byType(WebLoginPage), findsNothing);
      expect(find.text('课表学期'), findsNothing);
    },
  );

  testWidgets(
    'fetching selected undergrad semester reveals calendar sync controls',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'privacy_policy_accepted_20260914': true,
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
      expect(find.text('系统日历同步'), findsNothing);
      expect(find.text('已获取 2025-2026学年 第2学期'), findsOneWidget);
      expect(find.text('课程 1 门 · 考试 0 场 · 可导入 1 条'), findsOneWidget);
      expect(find.text('删除当前学期导入日程'), findsOneWidget);
      expect(find.text('一键清空本应用导入事件'), findsNothing);
    },
  );

  testWidgets(
    'schedule fetch requests full calendar permission only after confirmation',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'privacy_policy_accepted_20260914': true,
      });
      final calendarPlatform = WidgetFakeCalendarPlatform(
        permissionStatus: CalendarPermissionStatus.writeOnly,
        requestedPermissionStatus: CalendarPermissionStatus.granted,
      );
      DeviceCalendarPlusPlatform.instance = calendarPlatform;
      final scheduleService = WidgetFakeScheduleService(
        options: _semesterOptions(),
      );
      final calendarSyncService = WidgetFakeCalendarSyncService();

      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            authService: WidgetFakeAuthService(
              restoredSession: _undergradSession(),
            ),
            scheduleService: scheduleService,
            calendarSyncService: calendarSyncService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(calendarPlatform.permissionCheckCalls, 0);
      await tester.tap(find.text('拉取所选学期课表'));
      await tester.pumpAndSettle();

      expect(find.text('需要完整日历权限'), findsOneWidget);
      expect(calendarPlatform.permissionCheckCalls, 1);
      expect(calendarPlatform.permissionRequestCalls, 0);
      expect(scheduleService.scheduleFetchCalls, 0);
      expect(calendarSyncService.listWritableCalendarsCalls, 0);

      await tester.tap(find.widgetWithText(FilledButton, '确认'));
      await tester.pumpAndSettle();

      expect(calendarPlatform.permissionRequestCalls, 1);
      expect(scheduleService.scheduleFetchCalls, 1);
      expect(calendarSyncService.listWritableCalendarsCalls, 1);
      expect(find.text('已获取 2025-2026学年 第2学期'), findsOneWidget);
    },
  );

  testWidgets('denied full calendar permission blocks all loading', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'privacy_policy_accepted_20260914': true,
    });
    final calendarPlatform = WidgetFakeCalendarPlatform(
      permissionStatus: CalendarPermissionStatus.denied,
      requestedPermissionStatus: CalendarPermissionStatus.denied,
    );
    DeviceCalendarPlusPlatform.instance = calendarPlatform;
    final scheduleService = WidgetFakeScheduleService(
      options: _semesterOptions(),
    );
    final calendarSyncService = WidgetFakeCalendarSyncService();

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          authService: WidgetFakeAuthService(
            restoredSession: _undergradSession(),
          ),
          scheduleService: scheduleService,
          calendarSyncService: calendarSyncService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('拉取所选学期课表'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();

    expect(find.text('日历权限不足'), findsOneWidget);
    expect(calendarPlatform.permissionRequestCalls, 1);
    expect(scheduleService.scheduleFetchCalls, 0);
    expect(calendarSyncService.listWritableCalendarsCalls, 0);
  });

  testWidgets('a schedule request failure blocks the combined result', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'privacy_policy_accepted_20260914': true,
    });
    final scheduleService = WidgetFakeScheduleService(
      options: _semesterOptions(),
      scheduleError: Exception('学校课表接口失败'),
    );
    final calendarSyncService = WidgetFakeCalendarSyncService();

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          authService: WidgetFakeAuthService(
            restoredSession: _undergradSession(),
          ),
          scheduleService: scheduleService,
          calendarSyncService: calendarSyncService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('拉取所选学期课表'));
    await tester.pumpAndSettle();

    expect(find.text('拉取课表失败'), findsOneWidget);
    expect(find.text('学校课表接口失败'), findsOneWidget);
    expect(scheduleService.scheduleFetchCalls, 1);
    expect(calendarSyncService.listWritableCalendarsCalls, 1);
    expect(find.text('已获取 2025-2026学年 第2学期'), findsNothing);
  });

  testWidgets(
    'undergrad current-semester fallback warns before fetching schedule',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'privacy_policy_accepted_20260914': true,
      });
      final scheduleService = WidgetFakeScheduleService(
        options: _semesterOptionsWithMissingCurrent(),
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

      expect(scheduleService.fetchedSchedule, isFalse);
      expect(find.textContaining('未在学期列表中找到当前学期'), findsOneWidget);
      expect(find.textContaining('已默认选择 2025-2026学年 第2学期'), findsOneWidget);
    },
  );

  testWidgets(
    'selecting a non-current undergrad semester forwards full fetch arguments',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'privacy_policy_accepted_20260914': true,
      });
      final options = _semesterOptions();
      final scheduleService = WidgetFakeScheduleService(options: options);
      final selectedSemester = options.semesters.last;

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

      await tester.tap(find.byType(DropdownButtonFormField<NjuSemester>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(selectedSemester.name).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('拉取所选学期课表'));
      await tester.pumpAndSettle();

      expect(scheduleService.requestedSemesterId, selectedSemester.id);
      expect(scheduleService.requestedSemesterName, selectedSemester.name);
      expect(scheduleService.requestedSemesterStart, selectedSemester.start);
      expect(scheduleService.requestedSemesterEnd, selectedSemester.end);
      expect(scheduleService.requestedIncludeFinalExams, isTrue);
    },
  );

  testWidgets(
    'restored graduate session shows semester card before fetching schedule',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'privacy_policy_accepted_20260914': true,
      });
      final options = _semesterOptions();
      final scheduleService = WidgetFakeScheduleService(options: options);

      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            authService: WidgetFakeAuthService(
              restoredSession: _graduateSession(),
            ),
            scheduleService: scheduleService,
            calendarSyncService: WidgetFakeCalendarSyncService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(scheduleService.fetchedOptions, isFalse);
      expect(scheduleService.fetchedCurrentSchedule, isFalse);
      expect(find.text('课表学期'), findsNothing);
      expect(find.text('拉取当前学期课表'), findsOneWidget);
      expect(find.text('系统日历同步'), findsNothing);

      await tester.tap(find.text('拉取当前学期课表'));
      await tester.pumpAndSettle();

      expect(scheduleService.fetchedCurrentSchedule, isTrue);
      expect(find.text('系统日历同步'), findsNothing);
    },
  );

  testWidgets(
    'empty selected undergrad semester shows dialog without sync controls',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'privacy_policy_accepted_20260914': true,
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

  testWidgets('empty writable calendar list creates nju_calendar', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'privacy_policy_accepted_20260914': true,
    });
    final calendarPlatform = WidgetFakeCalendarPlatform();
    DeviceCalendarPlusPlatform.instance = calendarPlatform;

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          authService: WidgetFakeAuthService(
            restoredSession: _undergradSession(),
          ),
          scheduleService: WidgetFakeScheduleService(
            options: _semesterOptions(),
          ),
          calendarSyncService: CalendarSyncService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('拉取所选学期课表'));
    await tester.pumpAndSettle();

    expect(calendarPlatform.createdCalendarNames, ['nju_calendar']);
    expect(find.text('nju_calendar'), findsOneWidget);
    expect(find.text('已获取 2025-2026学年 第2学期'), findsOneWidget);
  });

  testWidgets('current-semester delete confirms before calling service', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'privacy_policy_accepted_20260914': true,
    });
    final calendarSyncService = WidgetFakeCalendarSyncService(
      calendars: const [
        Calendar(id: 'target-calendar', name: '个人日历', readOnly: false),
      ],
      deletedCount: 3,
    );
    final options = _semesterOptions();

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          authService: WidgetFakeAuthService(
            restoredSession: _undergradSession(),
          ),
          scheduleService: WidgetFakeScheduleService(options: options),
          calendarSyncService: calendarSyncService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('拉取所选学期课表'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(calendarSyncService.listWritableCalendarsCalls, 1);

    final deleteButton = find.widgetWithText(OutlinedButton, '删除当前学期导入日程');
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    expect(find.text('删除当前学期导入日程'), findsWidgets);
    expect(find.textContaining('2025-2026学年 第2学期'), findsWidgets);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(calendarSyncService.deleteCalls, 0);

    await tester.ensureVisible(deleteButton);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认删除'));
    await tester.pumpAndSettle();

    expect(calendarSyncService.deleteCalls, 1);
    expect(calendarSyncService.deletedCalendarId, 'target-calendar');
    expect(calendarSyncService.deletedBundle?.semesterId, '2025-2026-2');
    expect(find.text('已删除 3 条当前学期导入日程。'), findsOneWidget);
  });

  testWidgets(
    'web login page removes footer buttons but keeps app bar actions',
    (WidgetTester tester) async {
      WebViewPlatform.instance = WidgetFakeWebViewPlatform();

      await tester.pumpWidget(
        MaterialApp(
          home: WebLoginPage(
            schoolType: SchoolType.undergrad,
            authService: WidgetFakeAuthService(),
            usernameHint: '',
            automaticLogin: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('取消'), findsNothing);
      expect(find.text('我已完成登录'), findsNothing);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byKey(const Key('fake-webview')), findsOneWidget);
    },
  );

  testWidgets('saving unchanged credentials keeps the current session', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'privacy_policy_accepted_20260914': true,
    });
    final authService = WidgetFakeAuthService(
      restoredSession: _undergradSession(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          authService: authService,
          scheduleService: WidgetFakeScheduleService(
            options: _semesterOptions(),
          ),
          calendarSyncService: WidgetFakeCalendarSyncService(),
          settingsService: WidgetFakeSettingsService(
            const AutoLoginSettings(
              username: '123456789',
              password: 'password',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('配置登录信息'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存登录信息'));
    await tester.pumpAndSettle();

    expect(authService.clearSessionCalls, 0);
    expect(authService.clearWebViewCookiesCalls, 0);
    expect(find.text('课表学期'), findsNothing);
    expect(find.text('登录信息未变化，已保留当前登录态。'), findsOneWidget);
  });

  testWidgets('changing credentials clears the current session', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'privacy_policy_accepted_20260914': true,
    });
    final authService = WidgetFakeAuthService(
      restoredSession: _undergradSession(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          authService: authService,
          scheduleService: WidgetFakeScheduleService(
            options: _semesterOptions(),
          ),
          calendarSyncService: WidgetFakeCalendarSyncService(),
          settingsService: WidgetFakeSettingsService(
            const AutoLoginSettings(
              username: '123456789',
              password: 'password',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('配置登录信息'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'new-password');
    await tester.tap(find.text('保存登录信息'));
    await tester.pumpAndSettle();

    expect(authService.clearSessionCalls, 1);
    expect(authService.clearWebViewCookiesCalls, 1);
    expect(find.text('课表学期'), findsNothing);
    expect(find.text('登录信息已保存，请拉取学期信息。'), findsOneWidget);
  });

  testWidgets('semester fetch keeps automatic login embedded on home page', (
    WidgetTester tester,
  ) async {
    final backgroundPage = await _startBackgroundLogin(tester);
    expect(find.text('登录'), findsOneWidget);
    expect(find.byType(WebLoginPage), findsOneWidget);
    expect(backgroundPage.embedded, isTrue);
    expect(
      find.ancestor(
        of: find.byType(WebLoginPage),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byType(WebLoginPage),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );

    backgroundPage.onAutomaticLoginFailure!.call(
      const AutomaticLoginFailure(
        AutomaticLoginFailureType.sliderFailed,
        'NJU_SLIDER_FAILED_TWICE',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('自动登录失败'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '手动登录'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '手动登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final manualPage = tester.widget<WebLoginPage>(
      find.byType(WebLoginPage).last,
    );
    expect(manualPage.embedded, isFalse);
    expect(manualPage.automaticLogin, isFalse);
  });

  testWidgets('school page connection failure shows network dialog', (
    WidgetTester tester,
  ) async {
    final backgroundPage = await _startBackgroundLogin(tester);

    backgroundPage.onAutomaticLoginFailure!.call(
      const AutomaticLoginFailure(
        AutomaticLoginFailureType.network,
        '学校网页加载超过 5 秒',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('无法连接至学校网页'), findsOneWidget);
    expect(find.text('请检查网络连接。'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '知道了'), findsOneWidget);
    expect(find.text('手动登录'), findsNothing);
  });

  testWidgets('post-slider login failure shows credential error', (
    WidgetTester tester,
  ) async {
    final backgroundPage = await _startBackgroundLogin(tester);

    backgroundPage.onAutomaticLoginFailure!.call(
      const AutomaticLoginFailure(
        AutomaticLoginFailureType.invalidCredentials,
        'NJU_INVALID_CREDENTIALS',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('账号或密码有误'), findsOneWidget);
    expect(find.text('滑动验证码已通过，但未能完成登录。请检查保存的学号和密码。'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '知道了'), findsOneWidget);
    expect(find.text('手动登录'), findsNothing);
  });
}
