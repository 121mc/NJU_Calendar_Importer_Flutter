# NJU Calendar Importer Flutter - Program Structure Explanation

Date: 2026-03-07
Workspace: `e:\Programming\Peruses\NJU_Calendar_Importer_Flutter`

## 1. High-Level Purpose

This Flutter app helps users import university schedule data into the device's native calendar.

Core user journey:
1. Accept privacy policy.
2. Log in through official web SSO in an embedded WebView.
3. Capture authenticated cookies from WebView.
4. Use those cookies to call official schedule APIs.
5. Transform course/exam data into calendar events.
6. Write events to a selected system calendar.
7. Optionally remove previously imported events.

The architecture is a single-app-shell UI (`HomePage`) with several service classes handling side effects (storage, auth, network parsing, calendar sync).

## 2. Project Layout and Responsibilities

### Root-level configuration
- `pubspec.yaml`: Flutter package metadata, versions, and dependencies.
- `analysis_options.yaml`: Lint baseline (`flutter_lints`) with `avoid_print: true`.
- `README.md`: Product-level overview, usage, and disclaimers.

### `lib/` application code
- `main.dart`: App entry, UI composition, state machine, privacy gating, and user action handlers.
- `models/`: Domain and transport data models.
- `pages/`: Dedicated page for WebView login flow.
- `services/`: Business and integration logic.

### Platform directories
- `android/`: Android build + manifest permissions + app metadata.
- `ios/`: iOS app shell, plist permissions, pod settings.
- `docs/android_manifest_snippet.xml`, `docs/ios_info_plist_snippet.xml`: permission snippets for documentation/reference.

### Other
- `test/widget_test.dart`: Smoke test validating app bootstraps to `MaterialApp` and `HomePage`.
- `web/`: Default Flutter web shell files (not central to mobile flow).

## 3. Dependency-Level Architecture

Important dependencies from `pubspec.yaml`:
- `webview_flutter` + `webview_cookie_manager_flutter`: host official login page and read cookies.
- `dio` + `cookie_jar` + `dio_cookie_manager`: authenticated HTTP session and cookie propagation.
- `device_calendar_plus`: list/create/delete native calendar events.
- `flutter_secure_storage`: persist sensitive session JSON locally.
- `shared_preferences`: persist non-sensitive app flag (privacy accepted).
- `crypto`: SHA-1 generation for deterministic import keys in event descriptions.

Conceptually, this app has four boundaries:
1. UI boundary (Flutter widgets and state).
2. Auth/session boundary (cookie capture and session reconstruction).
3. Schedule API boundary (undergrad + graduate endpoint adapters).
4. Device calendar boundary (permission checks + event operations).

## 4. Runtime Flow in Detail

## 4.1 App startup
File: `lib/main.dart`

- `main()` runs `NjuScheduleCalendarApp`.
- `NjuScheduleCalendarApp` builds a `MaterialApp` with `HomePage` as root.
- `HomePage` initializes service instances in `initState()`:
  - `StorageService`
  - `AuthService`
  - `NjuScheduleService`
  - `CalendarSyncService`
- `_initializeApp()` reads privacy consent flag from `SharedPreferences`.
- If not accepted, a blocking dialog is shown before the app proceeds.

## 4.2 Privacy gating model

State flags in `HomePage`:
- `_privacyReady`: privacy state loaded from storage.
- `_privacyAccepted`: user has accepted policy.
- `_privacyDialogShowing`: avoids duplicate dialogs.
- `_bootstrapDone`: avoids repeating bootstrap logic.

Only after acceptance does app continue with:
- `_bootstrap()` (restore saved session).
- `_checkCalendarPermissionOnLaunch()` (permission prompt/validation).

This design enforces a clear compliance gate before session restore or permission behavior.

## 4.3 Login and session capture

Files:
- `lib/pages/web_login_page.dart`
- `lib/services/auth_service.dart`
- `lib/models/login_models.dart`

Flow:
1. User taps "open official login page".
2. `WebLoginPage` navigates to `AuthService.loginUrl?service=<school appShowUrl>`.
3. WebView navigation delegate tracks progress and URL transitions.
4. Once target area is reached (`ehall` / `ehallapp`), page attempts session capture.
5. `AuthService.captureSessionFromWebView()` reads cookies from multiple base URLs:
   - `https://authserver.nju.edu.cn`
   - `https://ehall.nju.edu.cn`
   - `https://ehallapp.nju.edu.cn`
6. Session is persisted via `StorageService.saveSession()` as secure JSON.
7. `SessionInfo` is returned to `HomePage` and stored in `_session`.

`SessionInfo` contains:
- `username` (local hint only)
- `schoolType` (`undergrad` / `graduate`)
- `cookiesByBaseUrl` map of serialized cookies (`StoredCookie`)

Backward compatibility:
- `SessionInfo.fromJson()` contains fallback logic for old format with only `CASTGC`.

## 4.4 Authenticated API access

`AuthService.buildAuthenticatedDio(session)`:
- Verifies that `ehallapp` cookies exist.
- Builds `Dio` with mobile browser-like user-agent and cookie manager.
- Seeds cookie jar for auth/ehall/ehallapp domains from persisted session.
- Performs an app index request to establish/validate server-side context.

Returned `Dio` client is then used by schedule service.

## 4.5 Schedule fetch and normalization

File: `lib/services/nju_schedule_service.dart`

Entry point:
- `fetchCurrentSemesterSchedule(SessionInfo, includeFinalExams)` routes to:
  - `_fetchUndergrad(...)`
  - `_fetchGraduate(...)`

### Undergrad path
- Calls current-semester endpoint, then semester metadata endpoint to get term anchor date.
- Calls course timetable endpoint and maps each row through `_mapUndergradCourse`.
- Optionally calls exam endpoint (`includeFinalExams`) and maps via `_mapUndergradExam`.
- Generates event descriptions containing import metadata.
- Sorts events chronologically and returns `ScheduleBundle`.

### Graduate path
- Fetches available semesters and picks latest eligible one (cutoff = now + 14 days).
- Normalizes semester anchor to Monday (`_normalizeWeekAnchorToMonday`).
- Fetches schedule rows, merges adjacent periods (`_mergeGraduateRows`).
- Fetches course list to enrich campus info.
- Maps rows via `_mapGraduateCourse` and returns `ScheduleBundle`.

### Parsing and robustness helpers
- `_ensureJsonMap`: defends against HTML redirects / non-JSON payloads, provides useful error preview.
- `_readRows`: safe path traversal for nested JSON API payloads.
- `_stringOrNull`, `_toInt`, date parsers, HHMM parsing helpers.
- `_sanitizeTeacher`: strips phone-like numbers from teacher fields.

Data model output:
- `ScheduleBundle` with `semesterName`, `events`, `courseCount`, `examCount`.
- `NjuCourseEvent` with title/time/location/description/importKey.

## 4.6 Calendar synchronization

File: `lib/services/calendar_sync_service.dart`

Permission model:
- `_ensurePermissions()` checks and optionally requests permission.
- Supports both `granted` and `writeOnly`.

Calendar operations:
- `listWritableCalendars()`: returns non-readonly calendars.
- `syncEvents(...)`:
  - Computes event window from bundle (`earliestStart`/`latestEnd`) +- 7 days.
  - If overwrite requested and permission is full (`granted`), scans old events and deletes those with marker `[NJU_SCHEDULE_IMPORT]`.
  - If only write-only permission, warns that overwrite cannot safely remove old events.
  - Creates new events with timezone `Asia/Shanghai` and busy availability.
  - Returns `CalendarSyncResult(created, deleted, skipped, warning)`.
- `deleteImportedEvents(calendarId)`:
  - Requires full read permission.
  - Scans a 5-year window (current year +-2) and removes events marked by app marker.

This marker-based strategy isolates app-created records from user-created records.

## 4.7 Storage strategy

File: `lib/services/storage_service.dart`

- Session JSON stored in secure storage under key `nju_session_json`.
- On decode failure, it clears broken/legacy keys to avoid repeated crashes.
- Also removes older legacy keys (`nju_username`, `nju_castgc`, `nju_school_type`).

Non-sensitive preference:
- Privacy acceptance stored in `SharedPreferences` key `privacy_policy_accepted_v1`.

## 5. UI Composition and State Machine

File: `lib/main.dart`

The `HomePage` UI is rendered as cards conditioned on state:
- Intro card (always visible once privacy accepted).
- Login card if no session.
- Session card when logged in.
- Fetch card after login.
- Schedule preview card after fetching schedule.
- Calendar sync card after schedule exists.

Action handlers:
- `_openWebLogin()`: launches `WebLoginPage`, stores returned session.
- `_logout()`: clears secure session and WebView cookies.
- `_loadSchedule()`: fetches current semester and stores `_bundle`.
- `_loadCalendars()`: reads writable device calendars.
- `_syncToCalendar()`: performs event import.
- `_deleteImportedEvents()`: explicit cleanup action with confirmation dialog.

The page uses many boolean guards (`_loggingIn`, `_loadingSchedule`, `_syncingCalendar`, etc.) to prevent duplicate concurrent actions and to drive loading indicators.

## 6. Platform Configuration

### Android
Files:
- `android/app/src/main/AndroidManifest.xml`
- `android/app/build.gradle.kts`
- `android/build.gradle.kts`

Manifest permissions:
- `INTERNET`
- `READ_CALENDAR`
- `WRITE_CALENDAR`

Gradle highlights:
- Kotlin + Flutter plugin setup.
- Java 11 target.
- Optional release signing loaded from `key.properties` if present.
- No minification/shrink in release currently.

### iOS
Files:
- `ios/Runner/Info.plist`
- `ios/Runner/AppDelegate.swift`
- `ios/Podfile`

Plist includes calendar usage strings (`NSCalendarsUsageDescription`, `NSCalendarsFullAccessUsageDescription`).
`AppDelegate` is standard Flutter registration shell.
Podfile sets iOS platform 13.0 and adds post-install build settings.

## 7. Testing and Quality Posture

File: `test/widget_test.dart`

Current test coverage is minimal: one smoke test ensures app bootstraps with `MaterialApp` and `HomePage`.

No dedicated tests currently exist for:
- Auth cookie capture behavior.
- API payload parsing and resilience.
- Calendar event generation correctness.
- Permission edge cases.

## 8. Design Characteristics and Tradeoffs

Strengths:
- Clear separation between UI, auth, schedule parsing, and calendar integration.
- Supports two different backend flows (undergrad/graduate) with dedicated mapping logic.
- Good defensive parsing against HTML redirects and malformed payloads.
- Marker-based calendar management avoids deleting unrelated user events.
- Local-only storage model aligns with privacy messaging.

Tradeoffs / coupling points:
- `main.dart` centralizes many responsibilities and state flags; very practical but large.
- API endpoint paths and response field names are tightly coupled to remote systems; upstream changes can break parsing.
- A lot of behavior is encoded in string keys from backend JSON; robust but fragile to schema drift.

## 9. File-by-File Summary (App Code)

- `lib/main.dart`: UI shell, startup orchestration, privacy gate, all user operations.
- `lib/pages/web_login_page.dart`: WebView login interaction and session completion triggers.
- `lib/services/auth_service.dart`: cookie extraction, session capture/persist bridge, authenticated `Dio` construction.
- `lib/services/nju_schedule_service.dart`: API fetching, JSON validation, domain mapping to calendar events.
- `lib/services/calendar_sync_service.dart`: permissions, calendar listing, event sync/deletion.
- `lib/services/storage_service.dart`: secure persistence and session recovery.
- `lib/models/login_models.dart`: login/session/cookie model types.
- `lib/models/nju_course.dart`: schedule and calendar sync result models.
- `lib/models/school_type.dart`: enum-driven branching metadata.

## 10. End-to-End Data Pipeline (Compact View)

1. User logs in via `WebLoginPage`.
2. `AuthService` reads cookies and creates `SessionInfo`.
3. `StorageService` persists session securely.
4. `NjuScheduleService` creates authenticated `Dio` and fetches timetable/exams.
5. Service maps backend rows to `NjuCourseEvent` list (`ScheduleBundle`).
6. `CalendarSyncService` writes events to selected native calendar.
7. Imported events are tagged with marker and `import_key` in description for future cleanup.

## 11. Overall Structural Assessment

The program is architected as a practical, service-oriented Flutter app with clear operational boundaries and a straightforward user flow. Its central risk is dependency on external institutional web/API contracts, but the internal structure is reasonably maintainable for a single-developer mobile utility application.
