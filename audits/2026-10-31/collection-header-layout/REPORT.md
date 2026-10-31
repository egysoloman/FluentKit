# Collection 分组头：窄尺寸约束、RTL 与自然内容宽度

日期：2026-10-31。接手基线 `073238a`，开始时工作区干净。此轮接续上一批 TreeView 报告中保留的 Grid 约束告警，不修改历史报告。

## 发现与源码依据

原有 `testGridResizeFitsRowsAndSectionHeadersInBothDirections` 能通过断言，但 XCTest 输出 `Conflicting constraints`，AppKit 会拆掉约束恢复布局，见 [before-resize.log](before-resize.log)。新复用测试在 RTL 的 12/1/0pt 宽度下另有三个几何断言失败，见 [before-reuse.log](before-reuse.log)。

原因是分组头给子内容安装了必需的左右边缘等式（各12pt），并将横向抗压缩优先级设为 required。当 header 宽度小于24pt时，等式要求负内容宽度；长标题还会与不可压缩要求冲突。默认头部也把按钮和组合内容拉到整行宽度，与 WinUI 的默认内容对齐不同。

本地 WinUI 2.3.1 源码依据：

- `src/dxaml/xcp/dxaml/themes/generic.xaml:9413–9480`：GridViewHeaderItem/ListViewHeaderItem 的 Padding 为12,8,12,0，HorizontalContentAlignment 为 Left；分隔线使用12,8,12,0边距且水平 Stretch。
- `src/dxaml/xcp/core/core/elements/framework.cpp:1833–1842`：安排时扣除 margin 后的可用宽度不得小于0；内容超过槽位时需要布局裁剪。
- `src/dxaml/xcp/core/core/elements/ContentPresenter.cpp:895–898`：只有 Stretch 使用全部可用宽度，其他对齐按子元素 DesiredSize 安排。

以上路径相对于仓库本地 `microsoft-ui-xaml-winui3-release-2.3.1/`。本轮没有使用 Windows 实机截图证明像素一致。

## 实现

`FluentSectionedCollectionHeader` 保留12pt前缘和8pt上边距，用 `max(0, headerWidth - 24)` 限制内容宽度；解除 required 抗压缩要求，允许长标题收缩。LTR/RTL 分别锚定物理左右边缘，窄到容不下边距时保留前缘语义并裁剪显示。分隔线独立占满扣除边距后的非负宽度。

默认内容按自然宽度靠前对齐。显式伸展的 Fluent 内容仍填满槽位，例如 `FluentVStack(alignment: .width)`。这是可见行为变化：自定义按钮不会再被强制拉满整行；已有48pt默认头部高度、吸顶开关和 ScrollIntoView 语义保留。自定义模板仍由调用方通过 `headerHeight` 指定槽位高度；模板截图使用60pt，容纳32pt按钮及上下间距。

CI 的 XCTest 步骤现在保留进程退出状态、捕获日志，并运行 [check_test_diagnostics.py](../../../tools/check_test_diagnostics.py)。它把 AppKit 约束冲突视为失败；编译器的 `-warnings-as-errors` 本身无法做到这一点。本地已验证检查器拒绝原始失败日志、接受最终日志；本轮未推送或运行远程 CI。

## 可复核的结果

- 旧的极窄 Grid 用例：断言通过但发出约束告警 → 最终断言通过且无该告警。
- 复用宽度600/180/24/12/1/0/360pt：LTR/RTL 均保持非负内容宽度，恢复正常宽度后边距恢复。
- 500pt宿主中的单按钮：476pt → 64pt；双按钮行：476pt → 134pt（含12pt间距）；显式 Stretch 仍为476pt，RTL 镜像前缘。
- 可见内容更换标题及切换 LTR/RTL 时，原生标题实例保持身份。
- 全量 XCTest：**266项，0失败**；新增3项分组头测试，另把既有 Grid 检查的横向留白从旧12pt总量收紧为24pt总量。最终测试日志未出现 AppKit 约束告警。
- Gallery Xcode Debug 构建通过，`CODE_SIGNING_ALLOWED=NO`。

- Release 门禁通过，60个直接 Gallery 示例完成 light/dark/RTL 挂载；`FluentKitValidation: PASS`。
- 独立 Release 探针：**40个尺寸/恢复状态 + 6个自定义模板状态全部通过**，见 [几何结果](after/visual/results.json) 与 [模板结果](after/visual/templates.json)。
- 22张最终截图。人工检查单按钮 LTR、双按钮 RTL、Stretch RTL 及 Grid 深色 RTL 吸顶状态；16张默认文字标题截图与本机修复前截图的 RGB 像素一致，见 [比较记录](after/default-image-comparison.json)。这只说明这些本机状态未发生视觉变化，不等同于 Windows 像素对照。
- 全量日志与门禁数据见 [after](after/)，告警检查器对修复前后的返回值见 [diagnostic-checks.txt](diagnostic-checks.txt)。Xcode 仍有无 AppIntents 依赖时跳过元数据提取的工具提示，不是 AppKit 约束告警。

所有几何结果均为当前 macOS 上的处理和布局结果，不等同于 Windows 像素验收。

## 数据说明与复跑

- [before/resize.json](before/resize.json) 和对应截图来自原始 Release 基线。
- [before/templates-after-clamp-before-alignment.json](before/templates-after-clamp-before-alignment.json) 是**中间版本**：已修宽度归零和裁剪、尚未修自然内容宽度。它专门记录拉伸问题，不能用于声称原始基线已经具备裁剪。
- 两个独立探针分别验证 List/Grid × light/dark × LTR/RTL × 5个窗口宽度，共40个尺寸/恢复状态；以及单按钮、双按钮、显式Stretch × LTR/RTL，共6个模板状态。恢复到320pt时还请求滚到条目45，并检查请求已清空；截图使用 `CALayer.render`。
- 原始 XCTest 告警通过 XCTest 日志可见；独立 AppKit 进程的 stderr 不一定输出同一条诊断。因此几何检查、完整 XCTest 日志与截图分别保留，不把空 stderr 当成单独充分的证据。

```sh
swift test --scratch-path /tmp/fluentkit-repair-tests -Xswiftc -warnings-as-errors > /tmp/fluentkit-tests.log 2>&1
python3 tools/check_test_diagnostics.py /tmp/fluentkit-tests.log
./tools/run-quality-checks.sh /tmp/fluentkit-header-quality
./audits/2026-10-31/collection-header-layout/run.sh /tmp/fluentkit-header-visual
```

本轮未完成 Windows 像素对照、真实触摸、IME、VoiceOver 验收；TreeView多条目拖动/展开动画与 CommandBar/MenuBar、AutoSuggestBox、SplitButton 的后续打磨仍待继续。
