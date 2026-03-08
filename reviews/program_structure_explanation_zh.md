# NJU Calendar Importer Flutter - 程序结构说明（中文）

日期：2026-03-07
工作区：`e:\Programming\Peruses\NJU_Calendar_Importer_Flutter`

## 1. 项目总体目标

这个 Flutter 应用用于把学校课表数据导入到手机系统日历中，方便在原生日历里统一查看课程与考试安排。

核心用户流程：
1. 同意隐私政策。
2. 在内嵌 WebView 中通过官方统一认证登录。
3. 从 WebView 捕获已认证的 Cookie。
4. 使用这些 Cookie 调用官方课表接口。
5. 将课程/考试数据转换成日历事件。
6. 写入用户选择的系统日历。
7. 可选：删除本应用此前导入的旧事件。

整体架构是一个单页面应用壳（`HomePage`）+ 多个服务类分工处理副作用（存储、认证、网络解析、日历同步）。

## 2. 项目目录与职责划分

### 根目录配置
- `pubspec.yaml`：Flutter 包信息、版本、依赖。
- `analysis_options.yaml`：Lint 规则基线（`flutter_lints`），并开启 `avoid_print: true`。
- `README.md`：产品介绍、使用说明、免责声明。

### `lib/` 应用代码
- `main.dart`：应用入口、UI 组织、状态机、隐私门禁、用户操作处理。
- `models/`：领域模型与会话/事件数据模型。
- `pages/`：专用页面（主要是网页登录流程）。
- `services/`：业务逻辑与系统集成逻辑。

### 平台目录
- `android/`：Android 构建脚本、权限清单、应用元数据。
- `ios/`：iOS 应用外壳、plist 权限文案、pod 配置。
- `docs/android_manifest_snippet.xml`、`docs/ios_info_plist_snippet.xml`：权限片段参考文档。

### 其他
- `test/widget_test.dart`：启动烟雾测试，确认应用能构建 `MaterialApp` 与 `HomePage`。
- `web/`：Flutter 默认 Web 外壳文件（不是移动端主流程重点）。

## 3. 依赖层面的架构说明

来自 `pubspec.yaml` 的关键依赖：
- `webview_flutter` + `webview_cookie_manager_flutter`：加载官方登录页并读取 Cookie。
- `dio` + `cookie_jar` + `dio_cookie_manager`：构建带 Cookie 的鉴权 HTTP 会话。
- `device_calendar_plus`：读取日历列表、创建/删除系统日历事件。
- `flutter_secure_storage`：本地安全存储会话 JSON。
- `shared_preferences`：持久化非敏感状态（如是否同意隐私政策）。
- `crypto`：生成稳定的 SHA-1 导入键（import key）。

从边界角度看，应用主要分为四层：
1. UI 边界（Flutter 组件与页面状态）。
2. 认证会话边界（Cookie 捕获与会话恢复）。
3. 课表 API 边界（本科/研究生两套接口适配）。
4. 系统日历边界（权限检测、写入与清理）。

## 4. 运行时流程详解

## 4.1 应用启动
文件：`lib/main.dart`

- `main()` 启动 `NjuScheduleCalendarApp`。
- `NjuScheduleCalendarApp` 构建 `MaterialApp`，首页为 `HomePage`。
- `HomePage.initState()` 初始化服务实例：
  - `StorageService`
  - `AuthService`
  - `NjuScheduleService`
  - `CalendarSyncService`
- `_initializeApp()` 从 `SharedPreferences` 读取隐私同意状态。
- 若未同意，会先弹出阻塞式隐私对话框，拦截后续流程。

## 4.2 隐私门禁模型

`HomePage` 关键状态位：
- `_privacyReady`：隐私状态是否已从本地加载完成。
- `_privacyAccepted`：用户是否已同意隐私政策。
- `_privacyDialogShowing`：防止重复弹框。
- `_bootstrapDone`：防止重复执行初始化恢复逻辑。

只有在同意后才继续：
- `_bootstrap()`：尝试恢复本地会话。
- `_checkCalendarPermissionOnLaunch()`：检查/申请日历权限。

这保证了合规门槛先于会话恢复和权限行为。

## 4.3 登录与会话捕获

相关文件：
- `lib/pages/web_login_page.dart`
- `lib/services/auth_service.dart`
- `lib/models/login_models.dart`

流程：
1. 用户点击“打开官方登录页”。
2. `WebLoginPage` 跳转到 `AuthService.loginUrl?service=<school appShowUrl>`。
3. WebView 通过导航回调跟踪进度和 URL 跳转。
4. 当 URL 进入目标区域（`ehall` / `ehallapp`）时尝试捕获会话。
5. `AuthService.captureSessionFromWebView()` 从多个基地址收集 Cookie：
   - `https://authserver.nju.edu.cn`
   - `https://ehall.nju.edu.cn`
   - `https://ehallapp.nju.edu.cn`
6. 通过 `StorageService.saveSession()` 以安全 JSON 方式持久化。
7. 将 `SessionInfo` 返回给 `HomePage` 并保存到 `_session`。

`SessionInfo` 内容：
- `username`（本地备注）
- `schoolType`（`undergrad` / `graduate`）
- `cookiesByBaseUrl`（序列化 Cookie 映射，元素类型 `StoredCookie`）

兼容性处理：
- `SessionInfo.fromJson()` 支持旧格式回退（只存 `CASTGC`）。

## 4.4 鉴权 API 访问

`AuthService.buildAuthenticatedDio(session)` 负责：
- 校验会话是否包含 `ehallapp` Cookie。
- 构建带移动端浏览器 UA 的 `Dio` 客户端。
- 将 auth/ehall/ehallapp 三域 Cookie 回灌到 `CookieJar`。
- 预请求 app index 页面以建立/确认服务端会话上下文。

返回后的 `Dio` 客户端由课表服务继续使用。

## 4.5 课表拉取与标准化

文件：`lib/services/nju_schedule_service.dart`

入口：
- `fetchCurrentSemesterSchedule(SessionInfo, includeFinalExams)`
  - 本科走 `_fetchUndergrad(...)`
  - 研究生走 `_fetchGraduate(...)`

### 本科路径
- 调当前学期接口，再调学期元数据接口，得到学期锚点日期。
- 调课表接口，逐行映射 `_mapUndergradCourse`。
- 若开启期末考试，调用考试接口并映射 `_mapUndergradExam`。
- 每条事件描述中写入导入元信息（含 marker 与 import key）。
- 最后按时间排序并返回 `ScheduleBundle`。

### 研究生路径
- 拉取可用学期，选择“当前时间 +14 天”范围内的最新可用学期。
- 将学期锚点归一化到周一（`_normalizeWeekAnchorToMonday`）。
- 拉取排课结果并合并相邻节次（`_mergeGraduateRows`）。
- 拉取教学任务列表，补充校区信息。
- 经 `_mapGraduateCourse` 映射为事件列表并返回 `ScheduleBundle`。

### 解析与健壮性辅助
- `_ensureJsonMap`：识别 HTML 重定向/非 JSON 响应，并给出可读错误预览。
- `_readRows`：按路径安全读取嵌套 JSON 列表。
- `_stringOrNull`、`_toInt`、日期解析、HHMM 转换等基础工具。
- `_sanitizeTeacher`：过滤教师字段中疑似手机号信息。

输出模型：
- `ScheduleBundle`：`semesterName`、`events`、`courseCount`、`examCount`。
- `NjuCourseEvent`：标题、时间、地点、描述、`importKey`。

## 4.6 系统日历同步

文件：`lib/services/calendar_sync_service.dart`

权限模型：
- `_ensurePermissions()` 先检查权限，必要时发起申请。
- 同时支持 `granted` 与 `writeOnly`。

核心操作：
- `listWritableCalendars()`：列出可写且非只读日历。
- `syncEvents(...)`：
  - 基于 `bundle` 的最早/最晚时间，构造查询窗口（前后各 7 天）。
  - 若选择覆盖且权限为 `granted`，先扫描旧事件并删除包含 marker `[NJU_SCHEDULE_IMPORT]` 的记录。
  - 若仅有 `writeOnly`，返回警告：无法读取旧事件，可能导致重复。
  - 逐条创建新事件，时区固定 `Asia/Shanghai`，忙碌状态 `busy`。
  - 返回 `CalendarSyncResult(created, deleted, skipped, warning)`。
- `deleteImportedEvents(calendarId)`：
  - 需要完整读取权限。
  - 扫描当前年份前后各两年（共 5 年）并删除含 marker 的导入事件。

该 marker 机制可避免误删用户自己创建的普通事件。

## 4.7 本地存储策略

文件：`lib/services/storage_service.dart`

- 会话 JSON 存于安全存储键 `nju_session_json`。
- 若解码失败，会主动清理损坏/旧数据，避免反复报错。
- 同时清理历史遗留键：`nju_username`、`nju_castgc`、`nju_school_type`。

非敏感配置：
- 隐私同意状态存于 `SharedPreferences` 键 `privacy_policy_accepted_v1`。

## 5. UI 结构与状态机

文件：`lib/main.dart`

`HomePage` 基于状态分段渲染卡片：
- 说明卡（同意隐私后常驻）。
- 未登录显示登录卡。
- 已登录显示会话卡。
- 登录后显示“拉取课表”卡。
- 拉取成功后显示课表预览卡。
- 有课表后显示系统日历同步卡。

主要动作处理函数：
- `_openWebLogin()`：打开 `WebLoginPage` 并接收会话。
- `_logout()`：清除安全存储会话与 WebView Cookie。
- `_loadSchedule()`：拉取当前学期并设置 `_bundle`。
- `_loadCalendars()`：读取可写系统日历。
- `_syncToCalendar()`：执行导入写入。
- `_deleteImportedEvents()`：二次确认后清理导入记录。

页面使用多个布尔锁（如 `_loggingIn`、`_loadingSchedule`、`_syncingCalendar`）来防重复点击并驱动加载态。

## 6. 平台配置说明

### Android
相关文件：
- `android/app/src/main/AndroidManifest.xml`
- `android/app/build.gradle.kts`
- `android/build.gradle.kts`

权限：
- `INTERNET`
- `READ_CALENDAR`
- `WRITE_CALENDAR`

Gradle 特点：
- Kotlin + Flutter 插件。
- Java 11 编译目标。
- 若存在 `key.properties`，自动读取发布签名配置。
- 当前 release 未开启代码压缩与资源裁剪。

### iOS
相关文件：
- `ios/Runner/Info.plist`
- `ios/Runner/AppDelegate.swift`
- `ios/Podfile`

`Info.plist` 包含日历权限文案（如 `NSCalendarsUsageDescription`、`NSCalendarsFullAccessUsageDescription`）。
`AppDelegate` 为标准 Flutter 注册流程。
`Podfile` 设定 iOS 最低版本 13.0 并带有 post-install 构建设置。

## 7. 测试与质量现状

文件：`test/widget_test.dart`

目前测试覆盖较轻，仅有一个启动烟雾测试，验证应用可正常构建到 `MaterialApp` 与 `HomePage`。

尚缺少针对以下模块的专项测试：
- Cookie 捕获与会话恢复。
- 各接口响应解析与异常回退。
- 事件映射准确性（时段、周次、地点等）。
- 日历权限边界场景（full / write-only / denied）。

## 8. 设计特点与权衡

优势：
- UI、认证、课表解析、日历同步职责边界清晰。
- 本科/研究生接口流程分离明确，便于维护。
- 对接口异常（HTML 重定向、非 JSON）有较强防御。
- 通过 marker 管理导入事件，降低误删风险。
- 本地存储策略与隐私声明一致（不走自建云端）。

权衡点：
- `main.dart` 状态与流程较集中，实用但体量偏大。
- 接口路径与字段名强依赖上游系统，易受接口变更影响。
- 许多逻辑依赖字符串字段键，稳妥但对 schema 漂移敏感。

## 9. App 代码逐文件摘要

- `lib/main.dart`：页面壳、启动编排、隐私门禁、主要用户动作。
- `lib/pages/web_login_page.dart`：WebView 登录交互与会话完成判定。
- `lib/services/auth_service.dart`：Cookie 采集、会话保存桥接、鉴权 `Dio` 构建。
- `lib/services/nju_schedule_service.dart`：接口调用、JSON 校验、事件映射。
- `lib/services/calendar_sync_service.dart`：权限处理、日历读取、导入/删除。
- `lib/services/storage_service.dart`：安全存储与会话恢复。
- `lib/models/login_models.dart`：登录会话与 Cookie 数据模型。
- `lib/models/nju_course.dart`：课表与同步结果模型。
- `lib/models/school_type.dart`：身份枚举与分支元信息。

## 10. 端到端数据流水线（简版）

1. 用户在 `WebLoginPage` 完成官方登录。
2. `AuthService` 读取 Cookie 并构造 `SessionInfo`。
3. `StorageService` 将会话安全持久化。
4. `NjuScheduleService` 构造鉴权 `Dio` 并拉取课表/考试。
5. 服务层把接口行数据映射为 `NjuCourseEvent`（组成 `ScheduleBundle`）。
6. `CalendarSyncService` 将事件写入用户选择的系统日历。
7. 导入事件在 description 中携带 marker 与 `import_key`，用于后续覆盖/清理。

## 11. 总体结构评价

该项目是一个典型的服务化 Flutter 工具应用：用户流程清晰、模块边界明确、实现务实，适合个人维护与持续迭代。主要技术风险集中在外部认证与课表接口的稳定性（上游变更可能导致解析失效），但现有内部结构已经具备较好的可读性与维护基础。
