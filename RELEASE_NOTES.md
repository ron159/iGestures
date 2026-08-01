# Release Notes / 更新说明

## v0.15.0 — 2026-08-01

### 中文

- 新增结构化诊断日志和 JSON 诊断报告导出，便于排查权限、事件监听、手势识别和动作执行问题。
- 诊断记录默认仅保存在内存；持久化需用户主动开启，并提供容量限制、日志轮转、七天保留和一键清除。
- 诊断报告包含应用与系统环境、权限状态和非敏感设置摘要，不包含原始手势轨迹、输入文本、URL、文件路径或脚本内容。
- 在“高级设置”中新增“导出诊断报告”操作和导出结果提示。
- 增加诊断报告、持久化开关、日志轮转和过期清理测试。

### English

- Added structured diagnostics and JSON report export for troubleshooting permissions, event taps, gesture recognition, and action execution.
- Diagnostics remain memory-only by default; persistent logging is opt-in, bounded, rotated, retained for seven days, and cleared when disabled.
- Reports include environment, permission, and non-sensitive settings summaries while excluding raw gesture paths, typed text, URLs, file paths, and script content.
- Added diagnostic report export and result feedback in Advanced Settings.
- Added coverage for report export, opt-in persistence, log rotation, and retention cleanup.
