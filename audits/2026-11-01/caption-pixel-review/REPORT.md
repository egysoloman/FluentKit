# 标题栏三键悬停边缘不一致

用户提供的录屏及先前的原始局部录屏均确认：最小化悬停背景未填满标题栏，最大化/关闭背景则越界。这是 `b2cec0c` 接入 Tooltip 包装时引入的布局回归，不是录屏缩放造成的假象。

原因：此前按 frame 布局 NSButton；接入 Tooltip 后，按钮四边改由 Auto Layout 的 alignment rect 约束。AppKit 对各 SF Symbol 返回不同 alignmentRectInsets：

| 32pt 标题栏 | 原按钮 frame | 对齐边距 top/left/bottom/right |
| --- | --- | --- |
| 最小化 | x0, y3, 46.5×27 | -2, 0, -3, 0.5 |
| 最大化 | x0, y-2.5, 46×37 | 2.5, 0, 2.5, 0 |
| 关闭 | x0, y-1.5, 46.5×36 | 2.5, 0, 1.5, 0.5 |

修复仅覆盖自绘 caption button 的 alignmentRectInsets，使背景、点击区和 Tooltip 宿主均使用完整槽位。没有改变通用 Tooltip 对其他原生控件的对齐规则。

验证：

- `CaptionGeometryAudit.swift`：32/40/48pt、三个按钮共 9 个原生状态。`before.json` 中 9 个 frame 不匹配，`after.json` 中归零。旧对象来自已验证的 Release 基线，新对象来自本次 Debug 构建。
- 新回归测试额外切换 Restore 的 `square.on.square` 图标，确认 glyph 变化不改变按钮区域。
- Tooltip 动画、材质配置和 caption 几何共 19 项相关测试通过，见 `focused-tests.log`。材质工作同时进行，不能把该日志称作仅 caption 补丁的独立完整门禁。
- `tooltip-follow-fixed.mp4` 为修复后的真实桌面合成局部录屏（沿用 `../tooltip-follow/recording/TooltipRecording.swift`）；三个 `*-fixed.png` 分别取最小化、最大化、关闭悬停帧，底边一致。录屏由自有窗口调用悬停入口，仍不等同于物理鼠标验收。
- Gallery Debug 构建通过，日志位于 `../material-options/gallery-build-first.log`。整个进行中批次的完整测试及 Release 门禁继续执行。

当前仍用 SF Symbols 绘制图标。本批确认并修复的是槽位/背景几何，不宣称完成 Windows 字形逐像素对照或多显示器验收。

补充复核：用户的 `ScreenRecording_11-01-2026 11-48-48_1.mov`（7.04 秒，1046×568；来源及 SHA-256 见 `user-recording.json`）再次逐帧确认同一悬停边界缺陷。当前 `d42b101` 修复已在后续 484 项测试中保留通过；本次没有重复修改 caption 代码。原生几何和桌面合成录屏支持本结论，不扩展为 Windows 字形或跨屏验收。
