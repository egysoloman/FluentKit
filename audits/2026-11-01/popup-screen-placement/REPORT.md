# 浮层选屏及屏幕变化通知

2026-11-01，跟进队列第 22 项的首批修复。基线 `f2fa4a858abe5062d748703c445621b6222d84cd`。该基线的 [CI #15](https://github.com/egysoloman/FluentKit/actions/runs/41288143387) 已通过：502 项测试、1 项平台能力跳过、0 失败，全产品 Release 与质量门禁通过；原始日志 `previous-batch-ci.log`。

## 源码与独立复现

本机 WinUI 归档 `microsoft-ui-xaml-winui3-release-2.3.1`：

- `src/dxaml/xcp/dxaml/lib/DXamlCore.cpp:3798–3896` 的 CalculateAvailableMonitorRect 将目标点转换到屏幕物理坐标，再调用 MonitorFromRect / MONITOR_DEFAULTTONEAREST，读取所选显示器工作区并换回逻辑坐标。
- `ComboBox_Partial.cpp:5227` 使用变换后的控件原点；`AutoSuggestBox_Partial.cpp:2058` 使用输入框的变换位置；`FlyoutBase_Partial.cpp:3393` 使用目标位置。RTL 的逻辑原点在右侧。
- [Microsoft MonitorFromRect 文档](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-monitorfromrect) 说明离屏时可选择最近显示器；[Apple NSWindow.screen](https://developer.apple.com/documentation/appkit/nswindow/screen) 是窗口所属屏幕，不能代替独立浮层目标位置。

旧 ComboBox、菜单、AutoSuggestBox、CommandBar 和文本命令浮层直接取 owner window 的 screen。跨屏窗口的目标可能已在另一块屏幕，模型反例保存于 `source-counterexamples.json`。这是源码可追踪的坐标反例，不是实际双屏操作记录。

另有可在本机独立复现的通知缺失：目标移动 80pt 后发送本进程的屏幕参数变化通知，已打开的浮层没有重新定位。相同 3 条 XCTest 在旧组件源码下全部失败，见 `before-native-tests.log`；替换及恢复的源文件摘要为 `before-test-source.json`。新几何帮助器在该次构建存在，但旧组件未调用它。

独立 Release 程序 `ScreenChangeAudit.swift` 覆盖 ComboBox、MenuFlyout、CommandBar overflow 与 CommandBarFlyout，深浅色 × LTR/RTL × 打开/通知后共 32 状态。旧版 16 个通知后状态全部停留原处，修复后全部跟随 80pt；面板、内容、first responder 身份不变，也不触发提交。前后原始 JSON、对象摘要及自身视图合成图为 `before/`、`after/`；检查结果为 `before-check.json`、`after-check.json`。

## 实现与验证范围

内部共享 resolver 按目标点选屏，对离屏点计算到屏幕矩形边缘的距离；没有将坐标乘以 backingScale。ComboBox/输入框使用逻辑起点，上下文菜单使用触发点，子菜单使用展开边，CommandBar 使用更多按钮位置。Tooltip 原本已有最近屏幕逻辑，本批归入共享实现；tab tear-out 的离屏点也沿用最近屏幕策略。

ComboBox、CommandBar overflow 和文本命令浮层增加随打开生命周期持有的观察器；菜单与 AutoSuggestBox 补齐 screen/backing/work-area 通知。重新定位保留既有面板和输入状态。普通窗口移动/缩放也通过同一现有几何路径处理；关闭/析构移除注册，其他窗口的事件不会调用该观察器。

10 项新回归覆盖左右/上下/负坐标排列、屏幕交界、RTL、最近边缘、空屏幕输入、原生通知、监听释放，以及 AutoSuggestBox 编辑器/模拟 marked text/选区保留。首轮相关 69 项有 1 项夹具失败：测试窗口没有取得 key 状态，且用固定队列轮数等待候选。改为与真实编辑路径相同的 key window 和可观察候选开启条件后，最终新增 10 项通过；原始失败保留在 `after-tests.log`，不将其误记为最终全过。

最终完整 **512 项测试、0 失败**；全产品 Release、Xcode Gallery 构建、原生验证及更新计数/身份/外部重置/字体/材质门禁全部通过。完整测试、原生验证及 Release 探针均无 AppKit 约束诊断，原始数据为 `full-tests.log`、`native-validation.log`、`release-build.log`、`gallery-build.log`、`quality/`。

## 尚未验收

当前只有内置 2× Retina 屏，环境信息见 `baseline-metadata.json`。上述通知由独立进程显式发送，marked text 也是客户端模拟；它们不证明真实热插拔、多屏排列变化、1×/2× 混合倍率或系统输入法候选行为。

原生材质仍由 AppKit 采样，本批没有改动材质后端或自行采样壁纸；跨屏壁纸、色域、半像素描边以及实际硬件仍在第 22 项。源码另见 ComboBox 的 preferredSize 尚未限制到短工作区/超长选项宽度，需要独立复现和后续修复。TeachingTip 的 root-bounds 策略保持现有契约，完整跨屏落点继续核对。

重跑：`zsh run-native.sh <SwiftPM products 目录> <新输出目录>`，再用 `python3 check_native.py <输出目录>/results.json` 检查。探针只操作自己的窗口，不修改显示器设置或运行中的 IME。
