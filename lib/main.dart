import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/login_models.dart';
import 'models/nju_course.dart';
import 'models/nju_semester.dart';
import 'models/school_type.dart';
import 'pages/generated_events_cleanup_page.dart';
import 'pages/web_login_page.dart';
import 'services/auth_service.dart';
import 'services/calendar_sync_service.dart';
import 'services/nju_schedule_service.dart';
import 'services/storage_service.dart';

void main() {
  runApp(const NjuScheduleCalendarApp());
}

class NjuScheduleCalendarApp extends StatelessWidget {
  const NjuScheduleCalendarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '呢喃课表导入',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B5CFF),
          primary: const Color(0xFF0B5CFF),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F6FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF5F6FA),
          foregroundColor: Color(0xFF202124),
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Color(0xFF202124),
            fontSize: 30,
            fontWeight: FontWeight.w900,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0B5CFF),
            foregroundColor: Colors.white,
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
            foregroundColor: const Color(0xFF0B5CFF),
            minimumSize: const Size.fromHeight(52),
            side: const BorderSide(color: Color(0xFF0B5CFF), width: 1.2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF1F2F4),
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
            borderSide: const BorderSide(color: Color(0xFF0B5CFF), width: 1.2),
          ),
        ),
        useMaterial3: true,
      ),
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
  static const _privacyAcceptedKey = 'privacy_policy_accepted_v1';

  late final StorageService _storageService;
  late final AuthService _authService;
  late final NjuScheduleService _scheduleService;
  late final CalendarSyncService _calendarSyncService;

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
  bool _permissionCheckRunning = false;
  bool _privacyAccepted = false;
  bool _privacyReady = false;
  bool _privacyDialogShowing = false;
  bool _bootstrapDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _storageService = StorageService();
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
      return;
    }

    await _showPrivacyConsentDialog();
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
                  '在你使用本应用前，请先阅读并同意《隐私政策》。本应用主要提供课表导入系统日历功能。为实现该功能，本应用会在你主动操作时访问官方登录页面，并在获得你授权后申请日历权限，以便读取系统日历列表、写入课表事件以及清理本应用此前导入的数据。\n\n'
                  '本应用不包含广告、不包含内购，也不会将你的账号、课表内容或日历数据上传到开发者自建服务器。相关数据仅在你的设备本地处理，并仅在访问官方系统时与学校服务器通信。',
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
      return;
    }

    await _loadSchedule();
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

    setState(() {
      _loggingIn = true;
    });
    try {
      final session = await Navigator.of(context).push<SessionInfo>(
        MaterialPageRoute(
          builder: (_) => WebLoginPage(
            schoolType: _schoolType,
            authService: _authService,
            usernameHint: '',
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

  Future<void> _logout() async {
    await _authService.clearSession();
    await _authService.clearWebViewCookies();

    if (!mounted) return;
    setState(() {
      _session = null;
      _bundle = null;
      _semesterOptions = const [];
      _selectedSemester = null;
      _semesterOptionsLoaded = false;
      _calendars = const [];
      _selectedCalendarId = null;
    });
    _showSnackBar('已清除登录态。');
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

      setState(() {
        _semesterOptions = options.semesters;
        _selectedSemester = options.currentSemester;
        _semesterOptionsLoaded = true;
      });
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

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
                      if (_session == null)
                        _buildLoginCard()
                      else
                        _buildSessionCard(),
                      if (_session?.schoolType == SchoolType.undergrad) ...[
                        const SizedBox(height: 12),
                        _buildSemesterCard(),
                      ],
                      if (_bundle != null) ...[
                        const SizedBox(height: 12),
                        _buildCalendarCard(),
                      ],
                      const SizedBox(height: 12),
                      _buildGeneratedEventsCleanupCard(),
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

  Widget _buildLoginCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '网页登录统一认证',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SegmentedButton<SchoolType>(
              segments: const [
                ButtonSegment(
                  value: SchoolType.undergrad,
                  label: Text('本科生'),
                  icon: Icon(Icons.school),
                ),
                ButtonSegment(
                  value: SchoolType.graduate,
                  label: Text('研究生'),
                  icon: Icon(Icons.auto_stories),
                ),
              ],
              selected: {_schoolType},
              onSelectionChanged: (value) {
                setState(() {
                  _schoolType = value.first;
                });
              },
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
                  : const Icon(Icons.language),
              label: const Text('打开官方登录页'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '当前登录态',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('身份：${_session!.schoolType.label}'),
            if (_loadingSchedule) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout),
                    label: const Text('退出并清空登录态'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSemesterCard() {
    final hasSemesterOptions = _semesterOptions.isNotEmpty;

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
            if (_loadingSemesters) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (!_loadingSemesters &&
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
            if (hasSemesterOptions) ...[
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
                    onPressed: _syncingCalendar ? null : _syncToCalendar,
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
          ],
        ),
      ),
    );
  }

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
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                '呢喃课表导入隐私政策',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 12),
              Text('生效日期：2026-03-03'),
              SizedBox(height: 16),
              Text(
                '1. 应用基本说明',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text('本应用用于帮助呢喃学生将课表与考试信息导入手机系统日历。本应用不提供社交、广告、支付或个性化推荐功能。'),
              Text('本项目是个人开发项目，与位于江苏省南京市的任何大学均无关。'),
              SizedBox(height: 16),
              Text(
                '2. 我们处理的信息',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text('为了实现课表导入功能，本应用可能在你主动操作时处理以下信息：'),
              Text('• 你在官方统一认证页面输入并完成认证所需的信息。'),
              Text('• 从官方系统返回的课表、考试、上课地点、教师等信息。'),
              Text('• 你授权后可访问的系统日历列表与本应用写入的日历事件。'),
              SizedBox(height: 16),
              Text(
                '3. 权限使用说明',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text('本应用会在获得你授权后申请日历权限，用于：'),
              Text('• 读取系统日历列表，供你选择导入目标日历；'),
              Text('• 将课表和考试信息写入系统日历；'),
              Text('• 删除本应用此前导入的旧事件，避免重复。'),
              SizedBox(height: 16),
              Text(
                '4. 数据传输与存储',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text('本应用不会将你的课表、日历内容或账号信息上传到开发者自建服务器。'),
              Text('本应用仅在你使用登录和课表拉取功能时，与官方系统进行网络通信。'),
              Text('必要的登录态、设置项或功能状态仅保存在你的设备本地，用于保证功能正常运行。'),
              SizedBox(height: 16),
              Text(
                '5. 第三方服务说明',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text('本应用依赖设备系统提供的日历能力，并通过应用内网页访问官方认证与课表系统。'),
              SizedBox(height: 16),
              Text(
                '6. 你的权利',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text('你可以拒绝授予日历权限，但届时将无法使用系统日历同步功能。'),
              Text('你可以在系统设置中关闭日历权限，或在应用内清除本应用导入的日历事件。'),
              SizedBox(height: 16),
              Text(
                '7. 联系方式',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text('维护者：mc_121'),
              Text('联系邮箱：mc_121_@outlook.com'),
            ],
          ),
        ),
      ),
    );
  }
}
