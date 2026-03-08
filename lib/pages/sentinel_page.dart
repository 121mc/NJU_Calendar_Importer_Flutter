import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/material.dart';
import 'package:nju_calendar_importer_flutter/utils/calendar_card.dart';
import 'package:nju_calendar_importer_flutter/utils/fetch_card.dart';
import 'package:nju_calendar_importer_flutter/utils/login_card.dart';
import 'package:nju_calendar_importer_flutter/utils/prompted_instruction_button.dart';
import 'package:nju_calendar_importer_flutter/utils/schedule_card.dart';
import 'package:nju_calendar_importer_flutter/utils/session_card.dart';

import '../models/login_models.dart';
import '../models/nju_course.dart';
import '../models/school_type.dart';

class SentinelPage extends StatelessWidget {
  const SentinelPage({
    super.key,
    required this.privacyReady,
    required this.onOpenPrivacyPolicy,
    required this.usernameHintController,
    required this.schoolType,
    required this.onSchoolTypeChanged,
    required this.loggingIn,
    required this.onOpenWebLogin,
    required this.session,
    required this.onLogout,
    required this.includeFinalExams,
    required this.onIncludeFinalExamsChanged,
    required this.loadingSchedule,
    required this.onLoadSchedule,
    required this.bundle,
    required this.calendars,
    required this.selectedCalendarId,
    required this.loadingCalendars,
    required this.onLoadCalendars,
    required this.onCalendarChanged,
    required this.overwritePreviousImports,
    required this.onOverwritePreviousImportsChanged,
    required this.syncingCalendar,
    required this.onSyncToCalendar,
    required this.deletingImportedEvents,
    required this.onDeleteImportedEvents,
  });

  final bool privacyReady;
  final VoidCallback onOpenPrivacyPolicy;
  final TextEditingController usernameHintController;
  final SchoolType schoolType;
  final ValueChanged<SchoolType> onSchoolTypeChanged;
  final bool loggingIn;
  final VoidCallback onOpenWebLogin;
  final SessionInfo? session;
  final VoidCallback onLogout;
  final bool includeFinalExams;
  final ValueChanged<bool> onIncludeFinalExamsChanged;
  final bool loadingSchedule;
  final VoidCallback onLoadSchedule;
  final ScheduleBundle? bundle;
  final List<Calendar> calendars;
  final String? selectedCalendarId;
  final bool loadingCalendars;
  final VoidCallback onLoadCalendars;
  final ValueChanged<String?> onCalendarChanged;
  final bool overwritePreviousImports;
  final ValueChanged<bool> onOverwritePreviousImportsChanged;
  final bool syncingCalendar;
  final VoidCallback onSyncToCalendar;
  final bool deletingImportedEvents;
  final VoidCallback onDeleteImportedEvents;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('呢喃课表导入'),
        actions: [
          IconButton(
            tooltip: '隐私政策',
            onPressed: onOpenPrivacyPolicy,
            icon: const Icon(Icons.privacy_tip_outlined),
          ),
        ],
      ),
      body: !privacyReady
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: SafeArea(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const SizedBox(height: 12),
                        if (session == null)
                          LoginCard(
                            usernameHintController: usernameHintController,
                            schoolType: schoolType,
                            onSchoolTypeChanged: onSchoolTypeChanged,
                            loggingIn: loggingIn,
                            onOpenWebLogin: onOpenWebLogin,
                          )
                        else
                          SessionCard(
                            session: session!,
                            onLogout: onLogout,
                          ),
                        if (session != null) ...[
                          const SizedBox(height: 12),
                          FetchCard(
                            session: session!,
                            includeFinalExams: includeFinalExams,
                            onIncludeFinalExamsChanged:
                                onIncludeFinalExamsChanged,
                            loadingSchedule: loadingSchedule,
                            onLoadSchedule: onLoadSchedule,
                          ),
                        ],
                        if (bundle != null) ...[
                          const SizedBox(height: 12),
                          ScheduleCard(bundle: bundle!),
                          const SizedBox(height: 12),
                          CalendarCard(
                            calendars: calendars,
                            selectedCalendarId: selectedCalendarId,
                            loadingCalendars: loadingCalendars,
                            onLoadCalendars: onLoadCalendars,
                            onCalendarChanged: onCalendarChanged,
                            overwritePreviousImports: overwritePreviousImports,
                            onOverwritePreviousImportsChanged:
                                onOverwritePreviousImportsChanged,
                            syncingCalendar: syncingCalendar,
                            onSyncToCalendar: onSyncToCalendar,
                            deletingImportedEvents: deletingImportedEvents,
                            onDeleteImportedEvents: onDeleteImportedEvents,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 20),
                    child: PromptedInstructionButton(),
                  ),
                ),
              ],
            ),
    );
  }
}
