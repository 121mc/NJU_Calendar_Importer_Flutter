import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_snack_bar.dart';
import 'models/login_models.dart';
import 'models/nju_course.dart';
import 'models/nju_semester.dart';
import 'models/school_type.dart';
import 'pages/settings_dialog.dart';
import 'privacy_policy.dart';
import 'pages/web_login_page.dart';
import 'services/auth_service.dart';
import 'services/calendar_sync_service.dart';
import 'services/nju_schedule_service.dart';
import 'services/settings_service.dart';
import 'services/storage_service.dart';

void main() {
  runApp(const NjuScheduleCalendarApp());
}

class NjuScheduleCalendarApp extends StatelessWidget {
  const NjuScheduleCalendarApp({super.key});

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0B5CFF),
      brightness: brightness,
      primary: isDark ? const Color(0xFFAEC6FF) : const Color(0xFF0B5CFF),
    );
    final scaffoldColor =
        isDark ? const Color(0xFF111318) : const Color(0xFFF5F6FA);
    final foregroundColor =
        isDark ? colorScheme.onSurface : const Color(0xFF202124);

    return ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldColor,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldColor,
        foregroundColor: foregroundColor,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: foregroundColor,
          fontSize: 30,
          fontWeight: FontWeight.w900,
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? const Color(0xFF1B1D23) : Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: isDark ? colorScheme.onPrimary : Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: colorScheme.primary, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Colors.black,
        contentTextStyle: TextStyle(color: Colors.white),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF24262D) : const Color(0xFFF1F2F4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.2),
        ),
      ),
      useMaterial3: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '呢喃课表导入',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.authService,
    this.scheduleService,
    this.calendarSyncService,
    this.settingsService,
  });

  final AuthService? authService;
  final NjuScheduleService? scheduleService;
  final CalendarSyncService? calendarSyncService;
  final SettingsService? settingsService;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _privacyAcceptedKey = 'privacy_policy_accepted_20260914';

  late final StorageService _storageService;
  late final AuthService _authService;
  late final NjuScheduleService _scheduleService;
  late final CalendarSyncService _calendarSyncService;
  late final SettingsService _settingsService;

  SessionInfo? _session;
  ScheduleBundle? _bundle;
  List<NjuSemester> _semesterOptions = const [];
  NjuSemester? _selectedSemester;
  List<Calendar> _calendars = const [];

  SchoolType _schoolType = SchoolType.undergrad;
  String? _selectedCalendarId;
  bool _loggingIn = false;
  bool _loadingSemesters = false;
  bool _semesterOptionsLoaded = false;
  bool _loadingSchedule = false;
  bool _syncingCalendar = false;
  bool _deletingCurrentSemesterEvents = false;
  bool _privacyAccepted = false;
  bool _privacyReady = false;
  bool _privacyDialogShowing = false;
  bool _bootstrapDone = false;
  bool _startupReloginAttempted = false;
  int _backgroundLoginAttempt = 0;

  AutoLoginSettings _autoLoginSettings = const AutoLoginSettings();

  @override
  void initState() {
    super.initState();

    _storageService = StorageService();
    _settingsService = widget.settingsService ?? SettingsService();
    _authService = widget.authService ?? AuthService(_storageService);
    _scheduleService =
        widget.scheduleService ?? NjuScheduleService(_authService);
    _calendarSyncService = widget.calendarSyncService ?? CalendarSyncService();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  Future<void> _initializeApp() async {
    final prefs = await SharedPreferences.getInstance();
    final accepted = prefs.getBool(_privacyAcceptedKey) ?? false;

    if (!mounted) return;

    setState(() {
      _privacyAccepted = accepted;
      _privacyReady = true;
    });

    if (accepted) {
      await _continueAfterPrivacyAccepted();
    } else {
      await _showPrivacyConsentDialog();
    }

    if (mounted && !_startupReloginAttempted) {
      await _loadAutoLoginSettings();
    }
  }

  Future<void> _loadAutoLoginSettings() async {
    try {
      final settings = await _settingsService.loadAll();
      if (!mounted) return;
      setState(() {
        _autoLoginSettings = settings;
      });
    } catch (_) {
      // Silently fail — settings are optional
    }
  }

  Future<void> _openSettingsDialog() async {
    await _loadAutoLoginSettings();
    if (!mounted) return;
    final previousSettings = _autoLoginSettings;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => SettingsDialog(settingsService: _settingsService),
    );
    if (saved == true) {
      await _loadAutoLoginSettings();
      if (!mounted) return;

      final credentialsChanged =
          previousSettings.username != _autoLoginSettings.username ||
              previousSettings.password != _autoLoginSettings.password;
      if (!credentialsChanged) {
        _showSnackBar('登录信息未变化，已保留当前登录态。');
        return;
      }

      await _authService.clearSession();
      await _authService.clearWebViewCookies();
      if (!mounted) return;
      setState(() {
        _schoolType = SchoolType.fromStudentId(_autoLoginSettings.username) ??
            SchoolType.undergrad;
        _session = null;
        _bundle = null;
        _semesterOptions = const [];
        _selectedSemester = null;
        _semesterOptionsLoaded = false;
        _calendars = const [];
        _selectedCalendarId = null;
      });
      _showSnackBar('登录信息已保存，请拉取学期信息。');
    }
  }

  Future<void> _continueAfterPrivacyAccepted() async {
    if (!_bootstrapDone) {
      _bootstrapDone = true;
      await _bootstrap();
    }
  }

  Future<void> _showPrivacyConsentDialog() async {
    if (!mounted || _privacyDialogShowing) return;
    _privacyDialogShowing = true;

    final agreed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('隐私政策与用户说明'),
              content: const SingleChildScrollView(
                child: Text(
                  '欢迎使用“呢喃课表导入”。\n\n'
                  '我们于2026年9月14日更新了隐私政策。\n\n'
                  '请阅读并同意新版《隐私政策》后继续使用。本应用不会将你的账号、验证码、课表内容或日历数据上传到开发者自建服务器。',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(false);
                  },
                  child: const Text('暂不同意'),
                ),
                TextButton(
                  onPressed: () async {
                    await Navigator.of(dialogContext).push(
                      MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyPage(),
                      ),
                    );
                  },
                  child: const Text('查看隐私政策'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: const Text('同意并继续'),
                ),
              ],
            );
          },
        ) ??
        false;

    _privacyDialogShowing = false;
    if (!mounted) return;

    if (!agreed) {
      setState(() {
        _privacyAccepted = false;
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_privacyAcceptedKey, true);

    if (!mounted) return;
    setState(() {
      _privacyAccepted = true;
    });

    await _continueAfterPrivacyAccepted();
  }

  Future<void> _openPrivacyPolicyPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
    );
  }

  Future<void> _bootstrap() async {
    final savedSession = await _authService.restoreSession();
    if (!mounted) return;
    if (savedSession != null) {
      setState(() {
        _session = savedSession;
        _schoolType = savedSession.schoolType;
      });
      final loaded = await _prepareScheduleForSession(showError: false);
      if (!loaded) {
        await _retryLoginAfterStartupFetchFailure();
      }
    }
  }

  Future<bool> _prepareScheduleForSession({bool showError = true}) async {
    final session = _session;
    if (session == null) return false;

    if (session.schoolType == SchoolType.undergrad) {
      return _loadSemesterOptions(showError: showError);
    }
    return true;
  }

  Future<void> _retryLoginAfterStartupFetchFailure() async {
    if (!mounted || _startupReloginAttempted || _loggingIn) return;
    _startupReloginAttempted = true;

    await _loadAutoLoginSettings();
    if (!mounted) return;

    if (!_autoLoginSettings.hasCredentials) {
      _showSnackBar('自动拉取学期信息失败，请先配置登录信息。');
      return;
    }

    final schoolType = SchoolType.fromStudentId(_autoLoginSettings.username);
    if (schoolType == null) {
      _showSnackBar('自动拉取学期信息失败，请检查保存的学号。');
      return;
    }

    _showSnackBar('登录状态已失效，正在自动重新登录…');
    await _authService.clearLoginCache();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    await _startBackgroundLogin(schoolType, clearSession: false);
  }

  Future<void> _openWebLogin() async {
    if (!_privacyAccepted) {
      _showSnackBar('请先同意隐私政策后再使用。');
      await _showPrivacyConsentDialog();
      return;
    }

    await _loadAutoLoginSettings();

    if (!_autoLoginSettings.hasCredentials) {
      _showSnackBar('请先配置正确的学号和密码。');
      await _openSettingsDialog();
      return;
    }
    final schoolType = SchoolType.fromStudentId(_autoLoginSettings.username);
    if (schoolType == null) {
      _showSnackBar('请检查学号是否为 9 位或 12 位数字。');
      await _openSettingsDialog();
      return;
    }

    await _startBackgroundLogin(schoolType);
  }

  Future<void> _startBackgroundLogin(
    SchoolType schoolType, {
    bool clearSession = true,
  }) async {
    if (clearSession) {
      await _authService.clearSession();
    }
    if (!mounted) return;
    setState(() {
      _schoolType = schoolType;
      _loggingIn = true;
      _backgroundLoginAttempt += 1;
      _session = null;
      _bundle = null;
      _semesterOptions = const [];
      _selectedSemester = null;
      _semesterOptionsLoaded = false;
      _calendars = const [];
      _selectedCalendarId = null;
    });
  }

  Future<void> _handleBackgroundLoginSuccess(
    int attempt,
    SessionInfo session,
  ) async {
    if (!mounted || !_loggingIn || attempt != _backgroundLoginAttempt) return;
    setState(() {
      _loggingIn = false;
      _session = session;
      _schoolType = session.schoolType;
      _bundle = null;
      _semesterOptions = const [];
      _selectedSemester = null;
      _semesterOptionsLoaded = false;
      _calendars = const [];
      _selectedCalendarId = null;
    });
    _showSnackBar('登录成功，已保存登录态。');
    await _prepareScheduleForSession();
  }

  Future<void> _handleBackgroundLoginFailure(
    int attempt,
    AutomaticLoginFailure failure,
  ) async {
    if (!mounted || !_loggingIn || attempt != _backgroundLoginAttempt) return;
    setState(() => _loggingIn = false);

    late final String title;
    late final String message;
    late final bool offersManualLogin;
    switch (failure.type) {
      case AutomaticLoginFailureType.network:
        title = '无法连接至学校网页';
        message = '请检查网络连接。';
        offersManualLogin = false;
        break;
      case AutomaticLoginFailureType.invalidCredentials:
        title = '账号或密码有误';
        message = '滑动验证码已通过，但未能完成登录。请检查保存的学号和密码。';
        offersManualLogin = false;
        break;
      case AutomaticLoginFailureType.sliderFailed:
        title = '自动登录失败';
        message = '连续两次滑动验证码均未通过，请改用手动登录。';
        offersManualLogin = true;
        break;
      case AutomaticLoginFailureType.other:
        title = '自动登录失败';
        message = failure.detail.trim().isEmpty
            ? '多次尝试后仍未能完成统一身份认证。'
            : '多次尝试后仍未能完成统一身份认证。\n\n${failure.detail}';
        offersManualLogin = true;
        break;
    }

    final openManualLogin = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              titlePadding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
              title: Row(
                children: [
                  Expanded(child: Text(title)),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(message),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(dialogContext).pop(offersManualLogin),
                    child: Text(offersManualLogin ? '手动登录' : '知道了'),
                  ),
                ],
              ),
            );
          },
        ) ??
        false;

    if (openManualLogin && mounted) {
      await _openManualWebLogin();
    }
  }

  Future<void> _openManualWebLogin() async {
    final session = await Navigator.of(context).push<SessionInfo>(
      MaterialPageRoute(
        builder: (_) => WebLoginPage(
          schoolType: _schoolType,
          authService: _authService,
          usernameHint: _autoLoginSettings.username,
          autoFillUsername: _autoLoginSettings.username,
          autoFillPassword: _autoLoginSettings.password,
          automaticLogin: false,
        ),
      ),
    );
    if (!mounted || session == null) return;

    setState(() {
      _session = session;
      _schoolType = session.schoolType;
      _bundle = null;
      _semesterOptions = const [];
      _selectedSemester = null;
      _semesterOptionsLoaded = false;
      _calendars = const [];
      _selectedCalendarId = null;
    });
    _showSnackBar('登录成功，已保存登录态。');
    await _prepareScheduleForSession();
  }

  Future<bool> _loadSemesterOptions({bool showError = true}) async {
    final session = _session;
    if (session == null || session.schoolType != SchoolType.undergrad) {
      return false;
    }

    setState(() {
      _loadingSemesters = true;
      _semesterOptionsLoaded = false;
      _semesterOptions = const [];
      _selectedSemester = null;
      _bundle = null;
    });

    try {
      final options =
          await _scheduleService.fetchUndergradSemesterOptions(session);
      if (!mounted) return false;

      final selectedSemester = options.currentSemester;
      setState(() {
        _semesterOptions = options.semesters;
        _selectedSemester = selectedSemester;
        _semesterOptionsLoaded = true;
      });
      if (selectedSemester != null && !options.hasMatchingCurrentSemester) {
        _showSnackBar(
          '未在学期列表中找到当前学期 ${options.currentSemesterName}，'
          '已默认选择 ${selectedSemester.name}。',
        );
      }
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _semesterOptionsLoaded = true;
      });
      if (showError) {
        _showSnackBar('加载学期列表失败：$e');
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _loadingSemesters = false;
        });
      }
    }
  }

  Future<void> _loadSchedule() async {
    final session = _session;
    if (session == null) return;

    final selectedSemester = _selectedSemester;
    if (session.schoolType == SchoolType.undergrad &&
        selectedSemester == null) {
      _showSnackBar('请先选择课表学期。');
      return;
    }

    if (!await _ensureFullCalendarPermission()) return;
    if (!mounted) return;

    final previousCalendarId = _selectedCalendarId;
    setState(() {
      _loadingSchedule = true;
      _bundle = null;
    });

    try {
      final Future<ScheduleBundle> scheduleFuture =
          session.schoolType == SchoolType.undergrad
              ? _scheduleService.fetchUndergradScheduleForSemester(
                  session,
                  semesterId: selectedSemester!.id,
                  semesterName: selectedSemester.name,
                  semesterStart: selectedSemester.start,
                  semesterEnd: selectedSemester.end,
                  includeFinalExams: true,
                )
              : _scheduleService.fetchCurrentSemesterSchedule(
                  session,
                  includeFinalExams: true,
                );
      final results = await Future.wait<Object>(
        [
          _calendarSyncService.listWritableCalendars(),
          scheduleFuture,
        ],
        eagerError: true,
      );
      if (!mounted) return;

      final calendars = results[0] as List<Calendar>;
      final bundle = results[1] as ScheduleBundle;
      if (calendars.isEmpty) {
        throw Exception('当前设备没有可写入的日历。');
      }

      if (bundle.events.isEmpty) {
        setState(() {
          _loadingSchedule = false;
        });
        await _showEmptyScheduleDialog(bundle.semesterName);
        return;
      }

      setState(() {
        _bundle = bundle;
        _calendars = calendars;
        _selectedCalendarId = calendars.any(
          (calendar) => calendar.id == previousCalendarId,
        )
            ? previousCalendarId
            : calendars.first.id;
      });
      _showSnackBar('已自动获取 ${bundle.events.length} 条日历事件。');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSchedule = false;
      });
      await _showMessageDialog(
        title: '拉取课表失败',
        message: _readableError(e),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingSchedule = false;
        });
      }
    }
  }

  Future<void> _showEmptyScheduleDialog(String semesterName) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('未查询到课表'),
          content: Text('$semesterName 暂未查询到课程或考试安排。'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _ensureFullCalendarPermission() async {
    try {
      final current = await DeviceCalendar.instance.hasPermissions();
      if (!mounted) return false;
      if (current == CalendarPermissionStatus.granted) return true;

      final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('需要完整日历权限'),
              content: const Text(
                '拉取课表前需要获取系统日历的完整访问权限，'
                '用于加载日历、覆盖旧日程并写入新课表。\n\n'
                '点击确认后，系统将显示日历权限申请。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('确认'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !mounted) return false;

      final requested = await DeviceCalendar.instance.requestPermissions();
      if (!mounted) return false;
      if (requested == CalendarPermissionStatus.granted) return true;

      final detail = requested == CalendarPermissionStatus.restricted
          ? '当前设备策略限制了日历权限。'
          : requested == CalendarPermissionStatus.writeOnly
              ? '当前只有写入权限，无法读取和覆盖旧日程。'
              : '未获得系统日历的完整访问权限。';
      await _showMessageDialog(
        title: '日历权限不足',
        message: '$detail\n\n请在系统设置中允许完整日历权限后重试。',
      );
      return false;
    } catch (e) {
      if (!mounted) return false;
      await _showMessageDialog(
        title: '日历权限检查失败',
        message: _readableError(e),
      );
      return false;
    }
  }

  Future<void> _showMessageDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  String _readableError(Object error) {
    final message = '$error';
    return message.startsWith('Exception: ')
        ? message.substring('Exception: '.length)
        : message;
  }

  Future<void> _syncToCalendar() async {
    if (_bundle == null) {
      _showSnackBar('课表还在自动获取中，请稍后再同步。');
      return;
    }
    if (_selectedCalendarId == null) {
      _showSnackBar('请先选择一个可写入的系统日历。');
      return;
    }

    setState(() {
      _syncingCalendar = true;
    });
    try {
      final result = await _calendarSyncService.syncEvents(
        calendarId: _selectedCalendarId!,
        bundle: _bundle!,
        overwritePreviousImports: true,
      );

      if (!mounted) return;
      final warning = result.warning == null ? '' : '\n${result.warning}';
      _showSnackBar(
        '同步完成：新增 ${result.created}，删除 ${result.deleted}，跳过 ${result.skipped}。$warning',
      );
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('写入系统日历失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _syncingCalendar = false;
        });
      }
    }
  }

  Future<void> _deleteCurrentSemesterImportedEvents() async {
    final bundle = _bundle;
    final calendarId = _selectedCalendarId;

    if (calendarId == null) {
      _showSnackBar('请先选择一个系统日历。');
      return;
    }
    if (bundle == null) {
      _showSnackBar('请先拉取要清理的学期课表。');
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('删除当前学期导入日程'),
            content: Text(
              '将删除当前目标日历中 ${bundle.semesterName} 由本应用导入的日程。'
              '其他学期带学期标记的导入日程不会被删除。',
            ),
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

    if (!mounted || !confirmed) return;

    setState(() {
      _deletingCurrentSemesterEvents = true;
    });
    try {
      final deleted = await _calendarSyncService.deleteGeneratedEventsForBundle(
        calendarId: calendarId,
        bundle: bundle,
      );

      if (!mounted) return;
      _showSnackBar('已删除 $deleted 条当前学期导入日程。');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('删除当前学期导入日程失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _deletingCurrentSemesterEvents = false;
        });
      }
    }
  }

  void _showSnackBar(String message) {
    showAppSnackBar(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final backgroundLoginAttempt = _backgroundLoginAttempt;
    return Scaffold(
      appBar: AppBar(
        title: const Text('呢喃课表导入'),
        actions: [
          IconButton(
            tooltip: '隐私政策',
            onPressed: _openPrivacyPolicyPage,
            icon: const Icon(Icons.privacy_tip_outlined),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_loggingIn && _privacyAccepted)
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  // Keep WKWebView fully rendered behind the opaque app UI.
                  // Making its native view transparent pauses both animation
                  // frames and timers on iOS, which can strand auto login.
                  child: WebLoginPage(
                    key: ValueKey(backgroundLoginAttempt),
                    schoolType: _schoolType,
                    authService: _authService,
                    usernameHint: _autoLoginSettings.username,
                    autoFillUsername: _autoLoginSettings.username,
                    autoFillPassword: _autoLoginSettings.password,
                    embedded: true,
                    onSession: (session) => _handleBackgroundLoginSuccess(
                      backgroundLoginAttempt,
                      session,
                    ),
                    onAutomaticLoginFailure: (detail) =>
                        _handleBackgroundLoginFailure(
                      backgroundLoginAttempt,
                      detail,
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: !_privacyReady
                  ? const Center(child: CircularProgressIndicator())
                  : !_privacyAccepted
                      ? _buildPrivacyBlockedView()
                      : SafeArea(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            children: [
                              _buildControlCard(),
                              if (_session != null) ...[
                                const SizedBox(height: 12),
                                _buildSemesterCard(),
                              ],
                              if (_bundle != null) ...[
                                const SizedBox(height: 12),
                                _buildCalendarCard(),
                              ],
                            ],
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyBlockedView() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.privacy_tip_outlined,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              const Text(
                '请先阅读并同意隐私政策',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text(
                '在你同意隐私政策前，本应用不会继续读取本地登录态，也不会申请日历权限或提供课表导入功能。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _showPrivacyConsentDialog,
                icon: const Icon(Icons.rule_folder_outlined),
                label: const Text('查看并同意隐私政策'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _openPrivacyPolicyPage,
                child: const Text('仅查看完整隐私政策'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: OutlinedButton.icon(
                onPressed: _loggingIn ? null : _openSettingsDialog,
                icon: const Icon(Icons.manage_accounts_outlined),
                label: const Text('配置登录信息'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: FilledButton.icon(
                onPressed: _loggingIn ? null : _openWebLogin,
                icon: _loggingIn
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download_outlined),
                label: const Text('登录'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSemesterCard() {
    final hasSemesterOptions = _semesterOptions.isNotEmpty;
    final isUndergrad = _session?.schoolType == SchoolType.undergrad;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUndergrad) ...[
              const Text('研究生课表系统将在拉取时自动确定当前学期。'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loadingSchedule ? null : _loadSchedule,
                icon: _loadingSchedule
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_for_offline),
                label: const Text('拉取当前学期课表'),
              ),
            ],
            if (isUndergrad && _loadingSemesters) ...[
              const LinearProgressIndicator(),
            ],
            if (isUndergrad &&
                !_loadingSemesters &&
                _semesterOptionsLoaded &&
                !hasSemesterOptions) ...[
              const Text('未获取到可选择的本科课表学期。'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loadSemesterOptions,
                icon: const Icon(Icons.refresh),
                label: const Text('重新加载学期列表'),
              ),
            ],
            if (isUndergrad && hasSemesterOptions) ...[
              DropdownButtonFormField<NjuSemester>(
                initialValue: _selectedSemester,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '选择要导入的学期',
                  border: OutlineInputBorder(),
                ),
                items: _semesterOptions
                    .map(
                      (semester) => DropdownMenuItem<NjuSemester>(
                        value: semester,
                        child: Text(semester.name),
                      ),
                    )
                    .toList(),
                onChanged: _loadingSchedule
                    ? null
                    : (semester) {
                        setState(() {
                          _selectedSemester = semester;
                          _bundle = null;
                        });
                      },
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loadingSchedule || _selectedSemester == null
                    ? null
                    : _loadSchedule,
                icon: _loadingSchedule
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_for_offline),
                label: const Text('拉取所选学期课表'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '已获取 ${_bundle!.semesterName}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '课程 ${_bundle!.courseCount} 门 · '
              '考试 ${_bundle!.examCount} 场 · '
              '可导入 ${_bundle!.events.length} 条',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedCalendarId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '选择写入目标日历',
                border: OutlineInputBorder(),
              ),
              items: _calendars
                  .map(
                    (calendar) => DropdownMenuItem(
                      value: calendar.id,
                      child: Text(calendar.name),
                    ),
                  )
                  .toList(),
              onChanged: _calendars.isEmpty
                  ? null
                  : (value) {
                      setState(() {
                        _selectedCalendarId = value;
                      });
                    },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        _syncingCalendar || _deletingCurrentSemesterEvents
                            ? null
                            : _syncToCalendar,
                    icon: _syncingCalendar
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.event_available),
                    label: const Text('写入系统日历'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _syncingCalendar || _deletingCurrentSemesterEvents
                            ? null
                            : _deleteCurrentSemesterImportedEvents,
                    icon: _deletingCurrentSemesterEvents
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_sweep),
                    label: const Text('删除当前学期导入日程'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('隐私政策'),
      ),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: SelectableText(privacyPolicyText),
        ),
      ),
    );
  }
}
