# ToggleSwitch 键盘提交时机

日期：2026-11-01。基线：`v0.2.0` / `1c0fa09`。本批属于发布之后的修复。

## 复现与参考契约

旧实现一次 Space keyDown 就改变 `isOn` 并发出回调，Return 也会切换。新增 9 项行为回归在旧代码中出现 44 个失败断言，见 `before-tests.log`；独立 Release 事件探针的原始状态见 `before-events.json`，来源记录为 `baseline-metadata.json`。

本机 WinUI 源码归档 `microsoft-ui-xaml-winui3-release-2.3.1` 中：

- `src/dxaml/xcp/dxaml/lib/ToggleSwitch_Partial.cpp:750–804`：KeyDown 记录是否处理，KeyUp 调用提交帮助器。
- 同文件 `HandlesKey`（1002 行）只接受 Space/GamepadA，不能把帮助器中的不可达方向键分支当成已启用的行为。
- `src/dxaml/xcp/components/controls/KeyDownUp/inc/ToggleSwitchKeyProcess.h`：Space 需要匹配的 KeyDown，释放时读取最新 `IsOn`；拖动期间不提交。
- `src/dxaml/xcp/dxaml/lib/Thumb_Partial.cpp:390–422`：指针按下就进入拖动捕获并发出 DragStarted，因此 Fluent 的 pointer pressed 阶段也应抑制新的键盘激活。

Space KeyDown 不改变 WinUI 的 pointer Pressed 状态；这里只增加待释放状态，没有给键盘按住添加鼠标按压形变。外部 IsOn 改变也不是取消键盘输入的信号。两点均保留在修复及回归中。

## 修复范围

`FluentToggle` 记录待释放 Space，在匹配的 KeyUp 清除记录后提交，避免重入复用同一次释放。Return、数字键盘 Enter 和方向键交给 responder 链；不新增控制器映射。

指针先按下时，Space 不提前提交也不取消鼠标操作。键盘先按下后再与指针重叠时，按 WinUI 的释放顺序处理：键盘先释放会被抑制；鼠标先完成后再释放已记录的 Space，两次独立释放各自生效。

保留既有外部绑定更新取消拖动的行为，同时不取消待释放的 Space；释放时切换最新模型值。辅助功能 press 立即提交，并消耗待释放状态。

AppKit 生命周期取消沿用本项目选择控件的约定：Escape、cancelOperation、禁用、隐藏（包括祖先隐藏）、移除/重挂载、焦点离开和窗口失去 key 状态后，不接受陈旧释放。取消后的自动重复不能重新激活，新的按下/释放仍可正常提交。这些是本机生命周期策略，不声称 WinUI 帮助器显式清理了所有同类状态。

## 验证

- 相关 Toggle/辅助功能 17 项通过；完整 XCTest **500 项、0 失败**，日志无 AppKit 约束诊断。
- 全产品 Release、Xcode Gallery 构建成功；扩展原生验证 **PASS**，新增实际 FluentState 绑定的 Space/Return/外部值更新断言。
- Release 更新计数、视图身份、外部重置、字体和材质门禁通过，原始结果为 `quality/`。
- 同一独立事件探针修复后：按下/重复时 false、0 次回调；释放后 true、1 次回调；Return、取消、禁用均不产生陈旧提交，辅助功能立即提交。见 `after-events.json`。

`KeyboardWindowProbe.swift` 另起独立 AppKit 应用，使用本进程的 local event monitor 记录事件派发之前的值，用 onValueChanged 记录提交。通过 CUA 操作这个窗口，不向正在运行的输入法发送测试输入。结果为 `cua-events.jsonl`：

| 操作 | 派发记录 | 回调结果 |
| --- | --- | --- |
| 按住 Space 约 0.926 秒 | keyDown / keyUp 前均为 false、0 次提交 | KeyUp 之后变为 true、1 次提交 |
| Return | keyDown / keyUp 均传到父 NSView | 保持 true、1 次提交 |
| 再按 Space 约 0.313 秒 | 释放前保持 true、1 次提交 | KeyUp 之后变为 false、2 次提交 |

该临时应用正常退出。`cua-app.log` 保留一条 macOS sandbox extension 提示；会话事件与退出结果均已核对，不将该日志描述为完全无诊断。这里验证的是自动化操作经过实际 AppKit 分发的结果，真实硬件长按、VoiceOver 操作及 Windows 同场景验收仍需专项测试。

重跑独立事件探针：`zsh run-events.sh <SwiftPM products 路径> <新的输出目录>`。支持 Swift Build 和 native SwiftPM 的产物布局。不要覆盖原始基线数据。
