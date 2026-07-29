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
- 支持触控板修饰键手势；
- 自定义触发键按住时长；按住时长或移动距离任一达到阈值即可开始手势；
- 内置八个可预览、复制和修改的预设，并提供首次引导与无动作练习模式；
- 可缩放的双栏手势工作区按全局、应用分组和单个应用管理映射；分组直接管理成员应用并共享手势；
- 单个应用手势优先于所属分组，分组手势未匹配时自动回退到全局手势；
- 手势列表与设置区显示留有边距的轨迹预览；
- 在手势页顶部直接设置全局触发键和按住时长，选中手势后可查看并切换全部动作类型；
- 在 SwiftUI 设置中创建、复制、搜索、重录、批量启停、排序和删除映射；
- 通过系统应用选择器配置作用域，无需手工填写 Bundle Identifier；
- 支持多显示器轨迹、识别结果反馈、三档灵敏度和可关闭的触觉反馈；
- 版本化 JSON 数据库、原子写入、损坏恢复、导入预览、合并、替换和撤销；
- Accessibility、Listen Event、Post Event 和 Event Tap 分项诊断；
- 可从权限页直接触发三项 macOS 系统授权流程，无需手动添加应用；
- 自动检查 GitHub 上最新的正式 Release，并在发现新版本时打开发布页面；
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

## 下载与安装

从 [GitHub Releases](https://github.com/ron159/iGestures/releases) 下载最新的
`iGestures-<版本>-macOS-arm64.zip` 和对应的 `.sha256` 文件。

1. 解压后将 `iGestures.app` 拖入 `/Applications`；
2. 尝试打开应用；
3. 如果 macOS 阻止首次打开，在“系统设置 → 隐私与安全性”中点击“仍要打开”；
4. 在 iGestures 权限页分别点击“授予权限”，按 macOS 提示确认辅助功能、
   输入监听和事件发送权限；
5. 如需登录后自动运行，在“通用”设置中打开“登录时启动”。

可以在终端校验下载文件：

```shell
shasum -a 256 -c iGestures-<版本>-macOS-arm64.zip.sha256
```

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

当前基线已通过 Debug/Release 构建、109 项 XCTest、Xcode Analyze、arm64 产物检查和
本地临时签名验证。GitHub Actions 会复跑格式、本地化、仓库卫生检查、核心检查、
XCTest 和 Release 构建。每次成功推送到 `main` 后，CI 会更新 `continuous`
预发布中的 ZIP 与 SHA-256 校验文件。

推送与 `MARKETING_VERSION` 对应的版本标签会创建版本化 Release。例如：

```shell
git tag -a v0.4.0 -m "iGestures 0.4.0"
git push origin v0.4.0
```

Release 工作流会验证标签与工程版本一致，运行格式检查、核心检查和 XCTest，
构建 arm64 应用，并发布版本化的 ZIP 与 SHA-256 校验文件。

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
