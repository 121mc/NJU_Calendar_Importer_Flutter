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
  });

  final AuthService? authService;
  final NjuScheduleService? scheduleService;
  final CalendarSyncService? calendarSyncService;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const _privacyAcceptedKey = 'privacy_policy_accepted_v2';

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
  bool _overwritePreviousImports = true;

  bool _loggingIn = false;
  bool _loadingSemesters = false;
  bool _semesterOptionsLoaded = false;
  bool _loadingSchedule = false;
  bool _loadingCalendars = false;
  bool _syncingCalendar = false;
  bool _deletingCurrentSemesterEvents = false;
  bool _permissionCheckRunning = false;
  bool _privacyAccepted = false;
  bool _privacyReady = false;
  bool _privacyDialogShowing = false;
  bool _bootstrapDone = false;

  AutoLoginSettings _autoLoginSettings = const AutoLoginSettings();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _storageService = StorageService();
    _settingsService = SettingsService();
    _authService = widget.authService ?? AuthService(_storageService);
    _scheduleService =
        widget.scheduleService ?? NjuScheduleService(_authService);
    _calendarSyncService = widget.calendarSyncService ?? CalendarSyncService();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _privacyAccepted) {
      _checkCalendarPermissionOnLaunch(silent: true);
    }
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

    if (mounted) {
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
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => SettingsDialog(settingsService: _settingsService),
    );
    if (saved == true) {
      await _loadAutoLoginSettings();
      if (mounted) {
        await _authService.clearSession();
        await _authService.clearWebViewCookies();
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
  }

  Future<void> _continueAfterPrivacyAccepted() async {
    if (!_bootstrapDone) {
      _bootstrapDone = true;
      await _bootstrap();
    }
    await _checkCalendarPermissionOnLaunch();
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
                  '隐私政策说明了本地保存的登录信息、内置 OCR、课表与日历数据处理方式。\n\n'
                  '请阅读并同意新版《隐私政策》后继续使用。本应用不包含广告或内购，也不会将你的账号、课表内容或日历数据上传到开发者自建服务器。',
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
      await _prepareScheduleForSession();
    }
  }

  Future<void> _prepareScheduleForSession() async {
    final session = _session;
    if (session == null) return;

    if (session.schoolType == SchoolType.undergrad) {
      await _loadSemesterOptions();
    }
  }

  Future<void> _checkCalendarPermissionOnLaunch({bool silent = false}) async {
    if (!_privacyAccepted || _permissionCheckRunning) return;
    _permissionCheckRunning = true;

    try {
      final status = await DeviceCalendar.instance.hasPermissions();

      if (!mounted) return;

      if (status == CalendarPermissionStatus.granted ||
          status == CalendarPermissionStatus.writeOnly) {
        return;
      }

      final requested = await DeviceCalendar.instance.requestPermissions();

      if (!mounted) return;

      if (requested == CalendarPermissionStatus.granted ||
          requested == CalendarPermissionStatus.writeOnly) {
        if (!silent) {
          _showSnackBar('已获得系统日历权限。');
        }
        return;
      }

      if (!silent) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('需要日历权限'),
            content: Text(
              requested == CalendarPermissionStatus.restricted
                  ? '当前设备策略限制了日历权限，无法使用系统日历同步功能。'
                  : '你尚未授予日历权限。没有该权限，本应用无法读取手机日历或写入课表事件。\n\n请在系统设置中允许“日历”权限后再试。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
      }
    } on DeviceCalendarException catch (e) {
      if (!mounted || silent) return;
      _showSnackBar('日历权限检查失败：${e.message}');
    } catch (e) {
      if (!mounted || silent) return;
      _showSnackBar('日历权限检查失败：$e');
    } finally {
      _permissionCheckRunning = false;
    }
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

    await _authService.clearSession();
    if (!mounted) return;
    setState(() {
      _schoolType = schoolType;
      _loggingIn = true;
      _session = null;
      _bundle = null;
      _semesterOptions = const [];
      _selectedSemester = null;
      _semesterOptionsLoaded = false;
      _calendars = const [];
      _selectedCalendarId = null;
    });
    try {
      final session = await Navigator.of(context).push<SessionInfo>(
        MaterialPageRoute(
          builder: (_) => WebLoginPage(
            schoolType: _schoolType,
            authService: _authService,
            usernameHint: _autoLoginSettings.username,
            autoFillUsername: _autoLoginSettings.hasCredentials
                ? _autoLoginSettings.username
                : null,
            autoFillPassword: _autoLoginSettings.hasCredentials
                ? _autoLoginSettings.password
                : null,
            backgroundLogin: true,
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
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('网页登录失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _loggingIn = false;
        });
      }
    }
  }

  Future<void> _loadSemesterOptions() async {
    final session = _session;
    if (session == null || session.schoolType != SchoolType.undergrad) return;

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
      if (!mounted) return;

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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _semesterOptionsLoaded = true;
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

  Future<void> _loadSchedule() async {
    final session = _session;
    if (session == null) return;

    final selectedSemester = _selectedSemester;
    if (session.schoolType == SchoolType.undergrad &&
        selectedSemester == null) {
      _showSnackBar('请先选择课表学期。');
      return;
    }

    setState(() {
      _loadingSchedule = true;
    });
    try {
      final bundle = session.schoolType == SchoolType.undergrad
          ? await _scheduleService.fetchUndergradScheduleForSemester(
              session,
              semesterId: selectedSemester!.id,
              semesterName: selectedSemester.name,
              semesterStart: selectedSemester.start,
              semesterEnd: selectedSemester.end,
              includeFinalExams: true,
            )
          : await _scheduleService.fetchCurrentSemesterSchedule(
              session,
              includeFinalExams: true,
            );
      if (!mounted) return;

      if (bundle.events.isEmpty) {
        setState(() {
          _bundle = null;
          _loadingSchedule = false;
        });
        await _showEmptyScheduleDialog(bundle.semesterName);
        return;
      }

      setState(() {
        _bundle = bundle;
      });
      _showSnackBar('已自动获取 ${bundle.events.length} 条日历事件。');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('自动获取课表失败：$e');
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

  Future<void> _loadCalendars() async {
    setState(() {
      _loadingCalendars = true;
    });
    try {
      final calendars = await _calendarSyncService.listWritableCalendars();
      if (!mounted) return;

      setState(() {
        _calendars = calendars;
        _selectedCalendarId = calendars.isEmpty
            ? null
            : (_selectedCalendarId ?? calendars.first.id);
      });

      if (calendars.isEmpty) {
        _showSnackBar('当前设备没有可写入的日历。');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('加载系统日历失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingCalendars = false;
        });
      }
    }
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
        overwritePreviousImports: _overwritePreviousImports,
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
      body: !_privacyReady
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              onPressed: _loggingIn ? null : _openSettingsDialog,
              icon: const Icon(Icons.manage_accounts_outlined),
              label: const Text('配置登录信息'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loggingIn ? null : _openWebLogin,
              icon: _loggingIn
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download_outlined),
              label: const Text('拉取学期信息'),
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
            const Text(
              '课表学期',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (!isUndergrad) ...[
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (isUndergrad &&
                !_loadingSemesters &&
                _semesterOptionsLoaded &&
                !hasSemesterOptions) ...[
              const SizedBox(height: 12),
              const Text('未获取到可选择的本科课表学期。'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loadSemesterOptions,
                icon: const Icon(Icons.refresh),
                label: const Text('重新加载学期列表'),
              ),
            ],
            if (isUndergrad && hasSemesterOptions) ...[
              const SizedBox(height: 12),
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
            const Text(
              '系统日历同步',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
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
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loadingCalendars ? null : _loadCalendars,
                    icon: _loadingCalendars
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.calendar_month),
                    label: const Text('加载手机日历'),
                  ),
                ),
              ],
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _overwritePreviousImports,
              onChanged: (value) {
                setState(() {
                  _overwritePreviousImports = value;
                });
              },
              title: const Text('覆盖删除本应用此前导入的旧事件'),
              subtitle: const Text('依赖读取权限；若只有写入权限则无法删除旧数据。'),
            ),
            const SizedBox(height: 8),
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
