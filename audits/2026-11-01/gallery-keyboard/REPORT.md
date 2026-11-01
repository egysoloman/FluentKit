# Gallery 动态页面键盘链与显式焦点循环

2026-11-01，基线 `7fa1dd4`。本批处理上一批真实 Gallery 中 Tab 停留在侧栏、无法进入 CheckBox 示例的问题。保留原始失败、修改中途结果和未关闭的搜索建议问题。

## 根因与修复

1. Gallery 和 FluentKit 的窗口工厂没有启用 `autorecalculatesKeyViewLoop`。初始页面建立键盘链后，导航加入的新 CheckBox 虽然 `canBecomeKeyView == true`，却没有进入原生链。真实 GalleryScreen、生产 `FluentWindowScene` 都复现。现为两个 Gallery、FluentWindowScene、分离标签窗口和 sheet 的自有窗口启用自动重建；嵌入调用者自建窗口的 FluentViewHost 不擅自改变其策略，README 补充接线说明。
2. 仅设置自动重建还不够：AppKit 的几何排序会绕过手工 `nextKeyView` 循环，使显式 scope 和 ContentDialog 的 Tab 逃出。现复用原有键盘 monitor，在最近的显式循环内处理普通 Tab/Shift-Tab；不拦截 Command/Control/Option-Tab 或循环外事件。循环候选仍经过 `canBecomeKeyView` 过滤。
3. 动态插入后，NSStackView 的 `subviews` 插入顺序可能为 A/B/C，而显示顺序为 A/C/B。scope 和对话框改按 `arrangedSubviews` 遍历。
4. 循环移动前转交文本控件的 Tab 命令代理，保留控件准备/消费导航的机会；组合文字交给原生输入法，结束编辑的验证仍可拒绝离开。已消费的 Tab 主动记录键盘设备，避免另一个 monitor 收不到事件而残留触摸密度。

Apple 的 [recalculateKeyViewLoop 文档](https://developer.apple.com/documentation/appkit/nswindow/recalculatekeyviewloop()) 说明该操作先使缓存失效，真正重建在后续导航发生。因此新控件刚插入时 `nextValidKeyView == nil` 不能独立判失败；本批比较的是实际导航后的链接和到达结果。最初错误的即时断言保留为 `comparison-before-lazy-correction.json`。

对照本地 WinUI `winui3-release-2.3.1` 的 `focusmgr.cpp`：270–318 行按当前焦点子集合遍历，480–510 行判断元素/祖先的 Cycle。源文件哈希见 `winui-source-sha256.txt`。本次落实键盘循环，不宣称完整 FocusManager 或程序化焦点 API 对等。

## 证据

| 验证路径 | 结果 |
| --- | --- |
| 实际 GalleryScreen 页面切换 | 旧版 Settings 导航不到新增正文控件；修改后进入正文，新增控件在导航时加入链 |
| 生产 FluentWindowScene 动态插入 | 自动重建/新增链接/可到达三项 false → true |
| 实际 sheet、分离标签窗口工厂 | 两条路径各三项条件通过，见 `after/windows.json` |
| 汇总 | `comparison.json`：5 项旧失败归零，最终 11 项条件通过 |
| 自动测试 | 最终运行时代码 438 项通过；随后增强测试中的稳定候选身份和延迟父级刷新，5 项定向测试通过 |
| 构建/门禁 | 最终 Release、Gallery Debug、FluentKitValidation、Release 质量门禁通过；日志在 `after/` |
| 实际 Gallery 窗口 | 从 Basic input → CheckBox，经 Tab 进入 Interactive sample，再 Tab/Space 改变复选状态；Shift-Tab 返回示例头及 Settings。先前还验证折叠跳过隐藏控件、展开后重新进入、RadioButton 的键盘激活 |
| 隔离交互 App | 自动重建后 B→A→C、Shift-Tab 回退；动态重排、对话框首尾循环与 Escape 恢复焦点通过。最终设备记录从 touch 经 Tab 变为 keyboard |

真实 Gallery 交互使用追加“消费事件记录设备”前的构建，哈希在 `after/gallery-provenance.json`；该普通页面不使用显式循环。最后追加的设备保护由最终 CycleApp 实际操作和测试验证，最终 Gallery 也重新构建。详细操作记录见 `after/ui-review.md`；不以主窗口截图代替输入法/VoiceOver 验收。

`after/initial-window-policy/` 是只加窗口选项时已通过的旧门禁，之后仍查出了循环逃逸；`after/pre-device-guard/` 是追加设备记录前的结果。保留这些结果说明常规门禁并未覆盖所有实际键盘行为。

## 搜索建议的独立未结项

`CandidateRefreshAudit.swift` 不含焦点 scope，直接使用 AppKit 编辑命令：Ap → Down 预览 Apple → 父级刷新 → Tab。每次重建候选 ID 时保留 Apple；使用稳定 ID 时恢复 Ap，见 `after/candidate-refresh.json`。源码在刷新时失去选中 ID，但留下预览文字；取消路径只在仍有选中项时恢复原查询。这条问题不依赖本次的 Tab 拦截器，需继续对照 WinUI 的候选替换语义。

实际 CycleApp 的稳定 ID 复验曾有一次 AX 仍显示 Apple，随后加入只读状态记录的复验恢复 Ap。两次结果均保留；不能据后一次成功宣布所有实际路径可靠。首次失败没有内部状态记录，尚需区分候选关闭/刷新时序与 AX 值刷新。本批仅证明文本命令代理被保留，没有把整个 AutoSuggestBox 标成验收结束。

另一个已确认差距：实际 Tab 从搜索框落到 Clear 按钮。上游 `AutoSuggestBox_themeresources.xaml` 241–242 行把 DeleteButton/QueryButton 设为 `IsTabStop=False`；框架尚未对齐。继续处理辅助按钮的键盘和可访问性契约，不能通过隐藏 AX 动作草率修正。

## 范围与复现

显式键盘循环不拦截 `NSWindow.selectNextKeyView` 或 `makeFirstResponder` 等程序化操作。`ScopeAudit.swift` 的 `selectedNext` 特意直接调用前者；自动重建时仍可能按 AppKit 几何顺序走出 scope，这份诊断不是最终键盘验收。程序化 FocusManager 对等、真实中文输入法 Tab/候选交互、完整 VoiceOver、Windows 实机对照继续开放。用户录屏候选条已确认是 macOS 自带拼音，相关客户端锚点另行跟踪。

```sh
swift build --target FluentKit -c release --scratch-path "$TMPDIR/fluentkit-quality-release" -Xswiftc -warnings-as-errors
zsh audits/2026-11-01/gallery-keyboard/run-probe.sh after
python3 audits/2026-11-01/gallery-keyboard/check-results.py
swift test --scratch-path /tmp/fluentkit-repair-tests --filter KeyboardFocusCycleTests -Xswiftc -warnings-as-errors
```

`before` 模式要求 `FLUENTKIT_KEY_PRODUCTS` 指向基线 Release 产品，不能用修后产品覆盖旧证据。GUI 探针、测试和 CUA 按串行执行。CycleApp 是一次性隔离应用；未安装、替换或停止用户运行中的 Fluent IME。本批没有修改 IME 源码。
