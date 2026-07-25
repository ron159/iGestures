# iGestures

iGestures 是一款原生 macOS 菜单栏鼠标手势工具：按住右键绘制自定义单笔轨迹，
松开后即可在当前应用中执行绑定的键盘快捷键。

项目采用原生 Swift 架构，围绕低延迟事件处理、可训练的自由轨迹、明确的失败回退
和本地数据隐私设计。

## 功能

- 录制任意单笔轨迹，每个手势最多保存五个训练样本；
- 绑定物理键码以及 Command、Option、Control、Shift、Fn 修饰键；
- 为映射设置全局、仅指定应用或排除指定应用的作用域；
- 在 SwiftUI 设置中创建、重命名、重录、启停、排序和删除映射；
- 通过系统应用选择器配置作用域，无需手工填写 Bundle Identifier；
- 实时轨迹覆盖层，可随时关闭；
- 版本化 JSON 数据库、原子写入、损坏恢复、导入和导出；
- Accessibility、Listen Event、Post Event 和 Event Tap 分项诊断；
- 使用 `SMAppService.mainApp` 管理登录时启动；
- 英文和简体中文界面。

## 系统要求

| 项目 | 要求 |
| --- | --- |
| macOS | 26.0 或更高版本 |
| Mac | Apple Silicon（仅 arm64） |
| 开发工具 | Xcode 27 |
| 语言 | Swift 6，Strict Concurrency |

应用目前使用开发 Bundle ID `com.ron159.igestures.dev` 和本地临时签名。
首次运行需要根据设置页提示授予系统权限；重新构建后，macOS 可能要求重新授权。

> 当前版本仍在开发中。Developer ID 签名、公证、Gatekeeper 分发以及完整的
> macOS 26/27 权限和交互矩阵尚未完成，不建议作为正式发行版分发。

## 构建与验证

用 Xcode 27 打开 `iGestures.xcodeproj`，选择共享 Scheme
`iGestures`。如果命令行仍使用 Command Line Tools，可临时指定 Xcode：

```shell
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
```

核心检查不依赖完整 XCTest 环境：

```shell
swift run iGesturesCoreChecks
swift run -c release iGesturesCoreChecks
```

运行完整测试：

```shell
xcodebuild test \
  -project iGestures.xcodeproj \
  -scheme iGestures \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/TestDerivedData \
  CODE_SIGNING_ALLOWED=NO
```

当前基线已通过 Debug/Release 构建、71 项 XCTest、Xcode Analyze、arm64 产物检查和
本地临时签名验证。GitHub Actions 会复跑格式、本地化、仓库卫生检查、核心检查、
XCTest 和 Release 构建。

## 设计概要

- `EventTapManager` 在专用高优先级 RunLoop 上处理鼠标事件；
- `GestureSession` 明确区分普通右键、轨迹跟踪、识别和 Fail-open 回放；
- `GestureNormalizer` 将输入归一化为固定点数，`GestureRecognizer` 使用轻量模板匹配；
- 设置修改通过不可变 `CompiledMappingSnapshot` 发布到事件线程；
- `OverlayEventBuffer` 合并跨线程更新，`OverlayController` 按显示帧绘制；
- `MappingStore` 使用 actor 隔离、完整校验、原子替换和恢复副本；
- 日常手势轨迹仅在内存中处理，不写入磁盘，不收集或上传用户数据。

## 项目结构

```text
iGestures/
├── App/          应用生命周期与状态
├── Core/         Event Tap、识别、映射和快捷键
├── Services/     权限、前台应用、偏好和登录项
├── UI/           SwiftUI 设置与 AppKit 覆盖层
├── Resources/    String Catalog 与 Privacy Manifest
└── Supporting/   Xcode 构建配置

iGesturesTests/       XCTest
iGesturesCoreChecks/  SwiftPM 核心检查
```

## 开源许可证

Copyright © 2026 ron159.

iGestures 采用 [GNU General Public License v3.0 or later](LICENSE)。
你可以使用、修改和二次发布本项目；如果对外分发原版或衍生版本，必须继续按照
GPL-3.0-or-later 提供对应源代码。
