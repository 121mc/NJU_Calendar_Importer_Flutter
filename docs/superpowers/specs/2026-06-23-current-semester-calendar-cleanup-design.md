# 当前学期导入日程删除按钮设计

## 背景

用户希望把“删除导入日程”的能力放回“系统日历同步”卡片最下面，但行为不再进入独立扫描页面。点击后先弹窗确认，然后只删除当前已拉取、当前选定学期在目标日历中的本应用导入课表事件。

当前应用已经具备两类相关能力：

- 同步写入时的“覆盖删除本应用此前导入的旧事件”逻辑，会根据当前 `ScheduleBundle` 的学期范围删除同学期旧事件。
- 独立“删除本软件生成的日程”页面会全量扫描各日历并按学期分组删除。

本设计只覆盖同步卡片里的“当前学期删除”快捷操作，不改独立删除页面的扫描和分组逻辑。

## 目标

在“系统日历同步”卡片底部新增一个按钮，用于删除当前目标日历中当前学期的本应用导入日程。

按钮行为必须满足：

- 只在已经成功拉取课表并展示同步卡片时出现。
- 需要用户已经选择写入目标日历。
- 点击后弹出确认对话框。
- 用户确认后执行删除。
- 删除范围与当前 `ScheduleBundle` 的学期范围一致。
- 删除匹配规则与同步写入前的覆盖删除一致。
- 不删除其他学期带 `semester_id` 的新格式事件。
- 可以删除当前学期范围内旧版本无 `semester_id` 的导入事件。

## 非目标

- 不重新设计独立“删除本软件生成的日程”页面。
- 不实现全设备、全日历扫描入口。
- 不修改 WebView 登录自动返回逻辑。
- 不自动创建或切换目标系统日历。
- 不在本功能中迁移旧版事件 description。

## 方案比较

推荐方案：新增一个服务方法 `deleteGeneratedEventsForBundle(calendarId, bundle)`，内部复用覆盖删除的同一套范围计算与匹配规则。UI 只负责确认、loading、错误提示和成功提示。

优点是行为和“覆盖删除”保持一致，不会出现两个入口删除范围不一样的问题；测试也能直接覆盖服务层的同学期删除规则。代价是需要从 `syncEvents` 中抽出一点重复删除逻辑。

备选方案一：UI 调用现有 `syncEvents`，传入空事件 bundle 并开启覆盖删除。这个方案改动少，但语义不清晰，会把“删除”伪装成一次同步，容易引入 created/skipped 统计误导。

备选方案二：复用独立清理页的扫描分组后按当前学期删除。这个方案能覆盖多日历，但它不符合“跟覆盖删除一样”的要求，且会再次触发当前全量扫描卡顿问题。

## 用户流程

用户先完成登录、拉取某个学期课表、加载手机日历并选择目标日历。

“系统日历同步”卡片展示：

1. 当前已获取学期和课程/考试数量。
2. 加载手机日历按钮。
3. 目标日历下拉框。
4. 覆盖删除开关。
5. 写入系统日历按钮。
6. 新增的“删除当前学期导入日程”按钮。

点击“删除当前学期导入日程”时：

1. 如果未选择目标日历，显示 SnackBar：`请先选择一个系统日历。`
2. 如果当前没有 `_bundle`，显示 SnackBar：`请先拉取要清理的学期课表。`
3. 如果条件满足，弹出确认对话框。
4. 对话框标题为：`删除当前学期导入日程`
5. 对话框内容说明将删除当前目标日历中当前学期由本应用导入的日程，并展示学期名。
6. 用户点“取消”时不执行任何删除。
7. 用户点“确认删除”后执行删除，并禁用写入/删除相关按钮。
8. 完成后用 SnackBar 显示：`已删除 X 条当前学期导入日程。`
9. 失败时用 SnackBar 显示：`删除当前学期导入日程失败：...`

## 数据流

UI 层使用现有状态：

- `_bundle` 提供 `semesterId`、`semesterName`、`semesterStart`、`semesterEnd`。
- `_selectedCalendarId` 提供目标日历。
- `_calendarSyncService` 执行系统日历读删。

新增 UI 状态：

- `_deletingCurrentSemesterEvents`：删除操作进行中时为 `true`。

新增 HomePage 方法：

- `_deleteCurrentSemesterImportedEvents()`

该方法负责参数校验、确认弹窗、调用服务、展示结果和恢复 loading 状态。

## 服务设计

`CalendarSyncService` 新增公开方法：

```dart
Future<int> deleteGeneratedEventsForBundle({
  required String calendarId,
  required ScheduleBundle bundle,
})
```

方法逻辑：

1. 调用 `_ensurePermissions()`。
2. 如果权限不是 `CalendarPermissionStatus.granted`，抛出与现有清理逻辑一致的完整读取权限错误。
3. 使用 `overwriteRangeFor(bundle)` 得到扫描范围。
4. 调用 `DeviceCalendar.instance.listEvents(range.start, range.end, calendarIds: [calendarId])`。
5. 遍历事件 description。
6. 使用 `CalendarImportMetadata.shouldDeleteForSemesterOverwrite(description, selectedSemesterId: bundle.semesterId)` 判断是否删除。
7. 优先用 `event.eventId` 删除；为空时回退 `event.instanceId`。
8. 单个事件删除失败时继续删除后续事件，保持现有覆盖删除容错策略。
9. 返回成功删除数量。

`syncEvents` 内部的覆盖删除也应改为调用同一个私有辅助方法，避免未来两个入口规则分叉。辅助方法可以命名为 `_deleteGeneratedEventsInRangeForSemester(...)`。

## 删除规则

本功能只删除满足以下条件的事件：

- 位于当前 `bundle` 的覆盖扫描范围内。
- 在当前选定 `calendarId` 对应日历中。
- description 被 `CalendarImportMetadata` 识别为本应用生成。
- 新格式事件带 `semester_id` 时，必须等于 `bundle.semesterId`。
- 旧格式事件无 `semester_id` 时，只要在当前扫描范围内即可删除。

这与当前覆盖删除设计一致：旧格式没有学期元数据，只能依赖“当前学期时间范围”来避免跨学期误删。

## UI 细节

按钮建议使用 `OutlinedButton.icon`，图标使用 `Icons.delete_outline` 或 `Icons.delete_sweep`。

按钮放在“写入系统日历”按钮下面，间距保持当前卡片节奏，例如 `SizedBox(height: 12)`。

当 `_syncingCalendar` 或 `_deletingCurrentSemesterEvents` 为 `true` 时，写入和删除按钮都禁用，避免并发读写同一个日历。

删除按钮 loading 时显示 16x16 的 `CircularProgressIndicator`，文字保持 `删除当前学期导入日程`，避免按钮宽度跳动过大。

## 错误处理

权限不足时服务层抛出：

`当前权限只能写入，无法读取已有事件；请在系统设置中授予完整日历权限后再试。`

UI 层不吞掉错误，直接在 SnackBar 中展示。

单个事件删除失败时服务层继续处理后续事件，不向 UI 暴露单项失败详情。这延续已有同步覆盖删除策略，避免一个异常事件阻塞整批删除。

如果没有找到可删除事件，服务返回 `0`，UI 显示 `已删除 0 条当前学期导入日程。`

## 测试计划

服务层测试：

- 当前学期删除只扫描 `overwriteRangeFor(bundle)` 对应范围。
- 当前学期删除只传入当前 `calendarId`。
- 新格式同学期事件会删除。
- 新格式其他学期事件不会删除。
- 旧格式无 `semester_id` 事件在当前学期范围内会删除。
- writeOnly 权限下抛出完整读取权限错误。

Widget 测试：

- 拉取课表并显示同步卡片后，能看到“删除当前学期导入日程”按钮。
- 未选择目标日历时点击按钮显示提示，不调用删除服务。
- 点击按钮后先出现确认弹窗。
- 取消确认不会调用删除服务。
- 确认后调用删除服务，并显示删除数量 SnackBar。
- 删除进行中时写入按钮和删除按钮禁用。

回归测试：

- 原有“写入系统日历”覆盖删除行为不变。
- 原有独立“删除本软件生成的日程”入口仍能打开。
- 研究生当前学期同步流程仍能看到并使用该按钮，因为研究生也有 `ScheduleBundle` 学期标识和范围。

## 验收标准

- 用户能在“系统日历同步”卡片底部看到删除当前学期导入日程按钮。
- 用户确认后，只删除当前选定目标日历、当前已拉取学期范围内的本应用导入事件。
- 删除结果有明确数量反馈。
- 权限不足、未选择日历、无当前课表结果时都有明确提示。
- `flutter test` 通过。
- `flutter analyze` 不新增问题。
