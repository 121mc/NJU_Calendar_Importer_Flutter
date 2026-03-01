# 南大课表导入手机日历（Flutter / WebView 登录版）

这是一个面向手机端的 Flutter 版本实现，登录方式改成了“官方网页登录 + 本地保存登录态”，不再自己抓统一认证验证码。

核心链路：

1. 在应用内打开南京大学统一认证 / eHall 官方页面登录。
2. 从 WebView Cookie 中提取 `CASTGC`。
3. 用 `CASTGC` 换取 eHall / 教务接口访问态。
4. 拉取当前学期课表（本科可选期末考试）。
5. 写入手机系统日历。

## 为什么改成 WebView 登录

你之前遇到的问题是：CAS 验证码接口直接返回 HTML，而不是图片。公开项目“南哪课表”采用的是“打开真实页面，再通过页面上下文取课表数据”的思路，而不是纯 HTTP 裸模拟登录。因此这个版本也改成了更接近该项目的认证方式：

- 登录交给官方网页
- 课表抓取与日历同步仍在 Flutter 本地完成

## 目录

- `lib/main.dart`：主界面
- `lib/pages/web_login_page.dart`：官方网页登录页
- `lib/services/auth_service.dart`：登录态保存、WebView Cookie 提取、Dio 认证桥接
- `lib/services/nju_schedule_service.dart`：本科 / 研究生课表接口解析
- `lib/services/calendar_sync_service.dart`：系统日历读写
- `docs/android_manifest_snippet.xml`：Android 需要合并的权限
- `docs/ios_info_plist_snippet.xml`：iOS 需要合并的权限

## 使用方式

### 1. 创建 Flutter 工程

```bash
flutter create --platforms=android,ios .
```

然后把本目录中的这些内容复制到新工程中：

- `lib/`
- `pubspec.yaml`
- `analysis_options.yaml`
- `docs/`

### 2. 安装依赖

```bash
flutter pub get
```

### 3. 配置权限

把 `docs/android_manifest_snippet.xml` 内容合并到：

- `android/app/src/main/AndroidManifest.xml`

把 `docs/ios_info_plist_snippet.xml` 内容合并到：

- `ios/Runner/Info.plist`

### 4. 运行

```bash
flutter run
```

## 当前能力

- 支持南京大学本科生 / 研究生
- 本科支持可选导入期末考试
- 支持安全保存登录态
- 支持再次同步前删除本应用之前导入的旧事件
- iOS 17+ 写入级权限下可新增事件，但不能读取旧事件进行覆盖删除

## 注意

1. 这个版本比“手动抓验证码”稳很多，但学校若未来调整统一认证和 eHall 流程，仍可能需要微调。
2. 由于当前环境不能真机编译，本项目属于“完整源码交付版”，建议你在本机 `flutter create` 后覆盖进去运行。
