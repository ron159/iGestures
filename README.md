# iGestures

iGestures 是一款原生 macOS 菜单栏鼠标手势工具：按住自定义触发鼠标键绘制单笔轨迹，
松开后即可在当前应用中执行绑定的键盘快捷键。

项目采用原生 Swift 架构，围绕低延迟事件处理、可训练的自由轨迹、明确的失败回退
和本地数据隐私设计。

## 功能

- 录制任意单笔轨迹，每个手势最多保存五个训练样本；
- 绑定物理键码以及 Command、Option、Control、Shift、Fn 修饰键；
- 支持 URL、应用、系统动作、Apple 快捷指令、动作序列和明确确认的受控脚本；
- 为映射设置全局、仅指定应用或排除指定应用的作用域；
- 应用专用映射优先，全局映射自动回退；
- 可从常用鼠标按键预设快速选择，或直接录制任意物理鼠标按键作为触发键；
- 每个映射可独立选择触发键、输入设备和 Repeat Mode；
- 支持默认关闭的 Rocker、“触发键 + 滚轮”与触控板修饰键手势；
- 自定义触发键按住时长；按住时长或移动距离任一达到阈值即可开始手势；
- 内置八个可预览、复制和修改的预设，并提供首次引导与无动作练习模式；
- 在 SwiftUI 设置中创建、复制、搜索、分类、重录、批量启停、排序和删除映射；
- 通过系统应用选择器配置作用域，无需手工填写 Bundle Identifier；
- 支持多显示器轨迹、识别结果反馈、三档灵敏度和可关闭的触觉反馈；
- 版本化 JSON 数据库、原子写入、损坏恢复、导入预览、合并、替换和撤销；
- Accessibility、Listen Event、Post Event 和 Event Tap 分项诊断；
- 本机有限诊断记录默认不跨启动保留，不记录轨迹、键入文本或窗口内容；
- 使用 `SMAppService.mainApp` 管理登录时启动；
- 英文和简体中文界面。

## 系统要求

| 项目 | 要求 |
| --- | --- |
| macOS | 26.0 或更高版本 |
| Mac | Apple Silicon（仅 arm64） |
| 开发工具 | Xcode 27 |
| 语言 | Swift 6，Strict Concurrency |

## 下载社区版

从 [GitHub Releases](https://github.com/ron159/iGestures/releases) 下载最新的
`iGestures-<版本>-macOS-arm64.zip` 和对应的 `.sha256` 文件。

社区版使用开发 Bundle ID `com.ron159.igestures.dev` 和 ad-hoc 签名，不包含
Apple Developer ID 签名或公证。macOS 无法验证开发者身份，首次打开需要手动批准：

1. 解压后将 `iGestures.app` 拖入 `/Applications`；
2. 尝试打开应用；
3. 打开“系统设置 → 隐私与安全性”，点击“仍要打开”；
4. 根据 iGestures 设置页提示授予辅助功能、输入监听和事件发送权限；
5. 如需登录后自动运行，在“通用”设置中打开“登录时启动”。

macOS 会将手动批准保存为本机例外。由于社区版没有稳定的 Developer ID 身份，
覆盖升级后可能需要重新批准应用或重新授予系统权限。

可以在终端校验下载文件：

```shell
shasum -a 256 -c iGestures-<版本>-macOS-arm64.zip.sha256
```

> 社区版是可供测试和日常使用的免费构建，不是经过 Apple 公证的正式分发版本。
> 受管理的 Mac 可能禁止手动放行未知开发者应用。

## 正式产品版

仓库同时保留独立的 `iGestures Formal Product Release` 工作流。它使用稳定 Bundle ID
`com.ron159.igestures`，执行 Developer ID Application 签名、Hardened Runtime、
Apple Notarization、Staple、Gatekeeper、arm64 和 macOS 26 最低版本验证，并生成
Ed25519 签名的更新清单。社区版工作流不会被标记为正式产品版。

正式工作流通过手动输入版本号触发，所需配置如下：

- GitHub Variables：`IGESTURES_UPDATE_PUBLIC_KEY`，内容为 32 字节 Ed25519 公钥的
  Base64；
- GitHub Secrets：`DEVELOPER_ID_APPLICATION`、`APPLE_DEVELOPMENT_TEAM`、
  `DEVELOPER_ID_P12_BASE64`、`DEVELOPER_ID_P12_PASSWORD`、
  `APPLE_NOTARY_KEY_ID`、`APPLE_NOTARY_ISSUER_ID`、
  `APPLE_NOTARY_PRIVATE_KEY` 和 `IGESTURES_UPDATE_PRIVATE_KEY`。

正式构建会内嵌只读的更新清单地址。应用自动检查或手动检查更新时，会依次验证 HTTPS、
清单签名、语义版本、系统版本、SHA-256、Bundle ID 和当前 Developer ID 的指定要求；
任一检查失败都不会替换当前应用。

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

当前基线已通过 Debug/Release 构建、99 项 XCTest、Xcode Analyze、arm64 产物检查和
本地临时签名验证。GitHub Actions 会复跑格式、本地化、仓库卫生检查、核心检查、
XCTest 和 Release 构建。每次成功推送到 `main` 后，CI 会更新 `continuous`
预发布中的 ZIP 与 SHA-256 校验文件。

推送与 `MARKETING_VERSION` 对应的版本标签会另外创建正式社区版 Release。例如：

```shell
git tag -a v0.3.0 -m "iGestures 0.3.0"
git push origin v0.3.0
```

社区 Release 工作流会验证标签与工程版本一致，运行格式检查、核心检查和 XCTest，
构建 ad-hoc 签名的 arm64 应用，并发布版本化的 ZIP 与 SHA-256 校验文件。

## 设计概要

- `EventTapManager` 在专用高优先级 RunLoop 上处理鼠标事件；
- `GestureSession` 明确区分普通触发键点击、轨迹跟踪、识别和 Fail-open 回放；
- `GestureNormalizer` 将输入归一化为固定点数，`GestureRecognizer` 使用轻量模板匹配；
- 设置修改通过不可变 `CompiledMappingSnapshot` 发布到事件线程；
- `OverlayEventBuffer` 合并跨线程更新，`OverlayController` 使用逐屏窗口按显示帧绘制；
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
