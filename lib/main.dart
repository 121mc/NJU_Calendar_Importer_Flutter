import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nju_calendar_importer_flutter/utils/intro_card.dart';
import 'package:nju_calendar_importer_flutter/utils/prompted_instruction_button.dart';
import 'package:nju_calendar_importer_flutter/utils/privacy_policy_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/login_models.dart';
import 'models/nju_course.dart';
import 'models/school_type.dart';
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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5E35B1)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const _privacyAcceptedKey = 'privacy_policy_accepted_v1';

  final _usernameHintController = TextEditingController();

  late final StorageService _storageService;
  late final AuthService _authService;
  late final NjuScheduleService _scheduleService;
  late final CalendarSyncService _calendarSyncService;

  SessionInfo? _session;
  ScheduleBundle? _bundle;
  List<Calendar> _calendars = const [];

  SchoolType _schoolType = SchoolType.undergrad;
  String? _selectedCalendarId;
  bool _includeFinalExams = true;
  bool _overwritePreviousImports = true;

  bool _loggingIn = false;
  bool _loadingSchedule = false;
  bool _loadingCalendars = false;
  bool _syncingCalendar = false;
  bool _deletingImportedEvents = false;
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
    _authService = AuthService(_storageService);
    _scheduleService = NjuScheduleService(_authService);
    _calendarSyncService = CalendarSyncService();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _usernameHintController.dispose();
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

    // if (accepted) {
    //   await _continueAfterPrivacyAccepted();
    //   return;
    // }

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
              content: SingleChildScrollView(
                child: IntroCard(),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(false);
                  },
                  child: const Text('暂不同意'),
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
      await SystemNavigator.pop();
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
        if (savedSession.username != '已登录用户') {
          _usernameHintController.text = savedSession.username;
        }
      });
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

    setState(() {
      _loggingIn = true;
    });
    try {
      final session = await Navigator.of(context).push<SessionInfo>(
        MaterialPageRoute(
          builder: (_) => WebLoginPage(
            schoolType: _schoolType,
            authService: _authService,
            usernameHint: _usernameHintController.text.trim(),
          ),
        ),
      );

      if (!mounted || session == null) return;

      setState(() {
        _session = session;
        _bundle = null;
      });
      _showSnackBar('登录成功，已保存登录态。');
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
      _calendars = const [];
      _selectedCalendarId = null;
    });
    _showSnackBar('已清除登录态。');
  }

  Future<void> _loadSchedule() async {
    if (_session == null) return;

    setState(() {
      _loadingSchedule = true;
    });
    try {
      final bundle = await _scheduleService.fetchCurrentSemesterSchedule(
        _session!,
        includeFinalExams: _includeFinalExams,
      );
      if (!mounted) return;

      setState(() {
        _bundle = bundle;
      });
      _showSnackBar('已拉取 ${bundle.events.length} 条日历事件。');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('拉取课表失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingSchedule = false;
        });
      }
    }
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
      _showSnackBar('请先拉取课表。');
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

  Future<void> _deleteImportedEvents() async {
    if (_selectedCalendarId == null) {
      _showSnackBar('请先选择一个目标日历。');
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('确认清空'),
              content: const Text(
                '将删除当前所选日历中由本应用导入的全部事件。\n\n不会删除你手动创建的普通日历事件。是否继续？',
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
            );
          },
        ) ??
        false;

    if (!confirmed) return;

    setState(() {
      _deletingImportedEvents = true;
    });

    try {
      final deleted = await _calendarSyncService.deleteImportedEvents(
        calendarId: _selectedCalendarId!,
      );

      if (!mounted) return;
      _showSnackBar('已删除 $deleted 条由本应用导入的日历事件。');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('清空失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _deletingImportedEvents = false;
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
          : Column(
              children: [
                Expanded(
                  child: SafeArea(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const SizedBox(height: 12),
                        if (_session == null)
                          _buildLoginCard()
                        else
                          _buildSessionCard(),
                        if (_session != null) ...[
                          const SizedBox(height: 12),
                          _buildFetchCard(),
                        ],
                        if (_bundle != null) ...[
                          const SizedBox(height: 12),
                          _buildScheduleCard(),
                          const SizedBox(height: 12),
                          _buildCalendarCard(),
                        ],
                      ],
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: PromptedInstructionButton(),
                  ),
                )
              ],
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
            TextField(
              controller: _usernameHintController,
              decoration: const InputDecoration(
                labelText: '账号备注（可选）',
                helperText: '只用于本地显示；真正登录将在官方网页中完成。',
                border: OutlineInputBorder(),
              ),
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
            const SizedBox(height: 8),
            Text(
              '说明：点击后会在应用内打开官方登录页面；完成统一认证后自动返回。',
              style: Theme.of(context).textTheme.bodySmall,
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
            Text('账号备注：${_session!.username}'),
            Text('身份：${_session!.schoolType.label}'),
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

  Widget _buildFetchCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '拉取课表',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (_session!.schoolType.supportsFinalExams)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _includeFinalExams,
                onChanged: (value) {
                  setState(() {
                    _includeFinalExams = value;
                  });
                },
                title: const Text('本科课表同时导入期末考试'),
              ),
            FilledButton.icon(
              onPressed: _loadingSchedule ? null : _loadSchedule,
              icon: _loadingSchedule
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: const Text('拉取当前学期课表'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleCard() {
    final bundle = _bundle!;
    final preview = bundle.events.take(8).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '课表预览',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('学期：${bundle.semesterName}'),
            Text('课程条目：${bundle.courseCount}'),
            Text('考试条目：${bundle.examCount}'),
            Text('最终生成事件数：${bundle.events.length}'),
            const SizedBox(height: 12),
            for (final item in preview)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(_formatDateTimeRange(item.start, item.end)),
                    if (item.location != null) Text(item.location!),
                  ],
                ),
              ),
            if (bundle.events.length > preview.length)
              Text('其余 ${bundle.events.length - preview.length} 条事件将在同步时写入日历。'),
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
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        (_deletingImportedEvents || _selectedCalendarId == null)
                            ? null
                            : _deleteImportedEvents,
                    icon: _deletingImportedEvents
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_sweep),
                    label: const Text('一键清空本应用导入事件'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTimeRange(DateTime start, DateTime end) {
    final mm = start.month.toString().padLeft(2, '0');
    final dd = start.day.toString().padLeft(2, '0');
    final sh = start.hour.toString().padLeft(2, '0');
    final sm = start.minute.toString().padLeft(2, '0');
    final eh = end.hour.toString().padLeft(2, '0');
    final em = end.minute.toString().padLeft(2, '0');
    return '$mm-$dd $sh:$sm ~ $eh:$em';
  }
}
