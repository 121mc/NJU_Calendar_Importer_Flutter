# Current Semester Calendar Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move generated-event deletion into the current semester sync card, remove the standalone cleanup page, and simplify the WebView login page footer.

**Architecture:** Reuse the same semester overwrite range and metadata matching for both sync-time overwrite deletion and the new explicit current-semester deletion action. Keep confirmation, loading state, and SnackBar feedback in `HomePage`, while `CalendarSyncService` owns device calendar reads/deletes.

**Tech Stack:** Flutter, Dart, device_calendar_plus, webview_flutter, flutter_test.

---

## File Structure

- Modify `lib/services/calendar_sync_service.dart`: add `deleteGeneratedEventsForBundle`, extract shared deletion helper, remove all-calendar scan/group deletion APIs used only by the deleted page.
- Modify `lib/main.dart`: remove `GeneratedEventsCleanupPage` import and card, add `_deletingCurrentSemesterEvents`, add `_deleteCurrentSemesterImportedEvents`, and add the sync-card delete button.
- Modify `lib/pages/web_login_page.dart`: remove the bottom `SafeArea` with the large cancel/manual-complete buttons.
- Delete `lib/pages/generated_events_cleanup_page.dart`.
- Modify `test/calendar_sync_service_test.dart`: add current-semester deletion tests and remove standalone scan/group tests.
- Modify `test/widget_test.dart`: remove navigation-to-cleanup-page expectations and add current-semester delete button/confirmation tests.
- Delete `test/generated_events_cleanup_page_test.dart`.

## Task 1: Service Method And Shared Deletion Rules

**Files:**
- Modify: `test/calendar_sync_service_test.dart`
- Modify: `lib/services/calendar_sync_service.dart`

- [ ] **Step 1: Write failing service tests**

Add tests that call:

```dart
final deleted = await CalendarSyncService().deleteGeneratedEventsForBundle(
  calendarId: 'target-calendar',
  bundle: bundle,
);
```

Assert that the method scans `CalendarSyncService.overwriteRangeFor(bundle)`, passes `calendarIds: ['target-calendar']`, deletes same-semester current marker events, skips other-semester current marker events, deletes legacy marker events in range, and throws `当前权限只能写入，无法读取已有事件；请在系统设置中授予完整日历权限后再试。` when permission is `writeOnly`.

- [ ] **Step 2: Run service tests and verify red**

Run:

```powershell
flutter test test/calendar_sync_service_test.dart
```

Expected: FAIL because `deleteGeneratedEventsForBundle` does not exist and removed standalone API tests still reference old behavior.

- [ ] **Step 3: Implement shared deletion helper**

Add this public method:

```dart
Future<int> deleteGeneratedEventsForBundle({
  required String calendarId,
  required ScheduleBundle bundle,
}) async {
  final permission = await _ensurePermissions();
  if (permission != CalendarPermissionStatus.granted) {
    throw Exception('当前权限只能写入，无法读取已有事件；请在系统设置中授予完整日历权限后再试。');
  }

  final range = overwriteRangeFor(bundle);
  return _deleteGeneratedEventsInRangeForSemester(
    calendarId: calendarId,
    range: range,
    semesterId: bundle.semesterId,
  );
}
```

Extract the existing overwrite deletion loop into `_deleteGeneratedEventsInRangeForSemester(...)` and call it from `syncEvents` when overwrite deletion is enabled and permission is granted.

- [ ] **Step 4: Remove standalone cleanup service APIs**

Delete `deleteImportedEvents`, `scanGeneratedEventGroups`, `deleteGeneratedEventGroup`, and `deleteGeneratedEventGroups` from `CalendarSyncService` after their tests and UI references are removed.

- [ ] **Step 5: Run service tests and verify green**

Run:

```powershell
flutter test test/calendar_sync_service_test.dart
```

Expected: PASS.

## Task 2: Home Page UI Integration

**Files:**
- Modify: `test/widget_test.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Write failing widget tests**

Update `WidgetFakeCalendarSyncService` to record `deleteGeneratedEventsForBundle` calls and return a configured deleted count. Add tests asserting:

```dart
expect(find.text('删除本软件生成的日程'), findsNothing);
expect(find.text('扫描并删除导入日程'), findsNothing);
expect(find.text('删除当前学期导入日程'), findsOneWidget);
```

Also test that tapping the new button without a selected calendar shows `请先选择一个系统日历。`, tapping with a selected calendar opens `删除当前学期导入日程`, canceling does not call the service, and confirming calls the service then shows `已删除 3 条当前学期导入日程。`.

- [ ] **Step 2: Run widget tests and verify red**

Run:

```powershell
flutter test test/widget_test.dart
```

Expected: FAIL because the standalone card is still present and the sync-card delete button does not exist.

- [ ] **Step 3: Implement homepage state and action**

Add `_deletingCurrentSemesterEvents`, `_deleteCurrentSemesterImportedEvents()`, and a sync-card `OutlinedButton.icon` with `Icons.delete_sweep`. Disable write/delete buttons while either sync or delete is running. Show a 16x16 `CircularProgressIndicator` while deleting and keep the label `删除当前学期导入日程`.

- [ ] **Step 4: Remove standalone cleanup card and import**

Delete the `GeneratedEventsCleanupPage` import, remove `_buildGeneratedEventsCleanupCard()`, and stop appending it to the main `ListView`.

- [ ] **Step 5: Run widget tests and verify green**

Run:

```powershell
flutter test test/widget_test.dart
```

Expected: PASS.

## Task 3: Web Login Footer Cleanup

**Files:**
- Modify: `lib/pages/web_login_page.dart`
- Modify or create: widget tests that cover visible login page controls

- [ ] **Step 1: Write failing WebLoginPage widget test**

Pump `WebLoginPage` with a fake WebView platform and assert:

```dart
expect(find.text('取消'), findsNothing);
expect(find.text('我已完成登录'), findsNothing);
expect(find.byIcon(Icons.refresh), findsOneWidget);
expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
```

- [ ] **Step 2: Run the WebLoginPage test and verify red**

Run:

```powershell
flutter test test/widget_test.dart
```

Expected: FAIL because the bottom footer buttons still render.

- [ ] **Step 3: Remove the bottom footer**

Delete the final `SafeArea(top: false, ...)` from `WebLoginPage.build`, leaving only the progress indicator, status `ListTile`, and `Expanded(WebViewWidget)`.

- [ ] **Step 4: Run widget tests and verify green**

Run:

```powershell
flutter test test/widget_test.dart
```

Expected: PASS.

## Task 4: Delete Standalone Page And Verify

**Files:**
- Delete: `lib/pages/generated_events_cleanup_page.dart`
- Delete: `test/generated_events_cleanup_page_test.dart`
- Read: all modified files

- [ ] **Step 1: Delete standalone page and page test**

Remove both files after all references are gone.

- [ ] **Step 2: Search for stale references**

Run:

```powershell
rg "GeneratedEventsCleanupPage|generated_events_cleanup|scanGeneratedEventGroups|deleteGeneratedEventGroup|deleteGeneratedEventGroups|deleteImportedEvents"
```

Expected: no live Dart references remain.

- [ ] **Step 3: Format, test, and analyze**

Run:

```powershell
dart format lib test
flutter test
flutter analyze
```

Expected: all tests pass and analyzer reports no new issues.

## Self-Review

Spec coverage:

- The new button lives inside the sync card and uses the current `ScheduleBundle` plus selected target calendar.
- The delete service uses the same overwrite range and `CalendarImportMetadata.shouldDeleteForSemesterOverwrite` rule as sync overwrite deletion.
- Standalone cleanup page, card, and page test are removed.
- WebView login footer buttons are removed while AppBar refresh and completion icons remain.

Placeholder scan:

- The plan has exact files, methods, button labels, messages, and commands.

Type consistency:

- Method names match the design doc: `deleteGeneratedEventsForBundle` and `_deleteGeneratedEventsInRangeForSemester`.
