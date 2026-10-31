# AutoSuggestBox 输入、候选列表与布局复核

日期：2026-10-31。基线：`d6855f3`。本批修复 AutoSuggestBox；SplitButton 留在后续批次。
开始时工作区干净。旧审计目录未修改。本目录保存独立复现脚本、原始输出和 2× layer tree 截图。
截图固定浅/深色主题并关闭材质效果，用于核对布局；不是 Windows 材质像素比较。

## 独立确认的问题

新增的首轮 7 个回归测试在未修改运行时代码时产生 **16 处失败**，见
[原始失败输出](before/regression-tests.log)。Release 探针覆盖浅/深色 × LTR/RTL × 4 个状态，见
[修复前数据](before/results.json)和[构建对象 SHA-256](before/library-sha256.txt)。

1. **候选列表没有滚动容器。** 20 项放进 84pt 弹窗后，键盘可以选到最后一项，但该行的可见高度为 0；无法通过滚动访问。行也没有暴露 accessibility selected 状态。
2. **Escape 的界面值和模型分离。** 预览 `Apple 0` 后 Escape 显示 `Ap`，绑定仍为 `Apple 0`。关闭后 Down 还会重新打开旧列表并选择条目。
3. **外部重置保留过期候选。** 模型清空后原弹窗仍显示；Enter 能提交清空前选中的候选。
4. **实时更新不完整。** 更换 provider、重排数据或把最大高度从 84 改到 164，不会更新已打开的列表。原实现仅改变 panel 内容大小，没有随高度重新定位，也没有更新 reveal clip。
5. **标题超出控件分配的高度。** field 已经放在顶部，header 又放在 field 上方。截图中的 header 仍可能可见，但越过自身 bounds，在真正的 stack 中会占用邻居区域。
6. **RTL 只改了外层方向。** 查询/清除按钮仍在右边，编辑区域和候选图标/文本没有镜像。
7. **事件与生命周期缺口。** Escape 不能阻止等待中的 debounce 重新开窗；focus 会误发 TextChanged；没有变化原因；最大高度 0 和负值的语义不符 WinUI。

## WinUI 源码依据

本地 `microsoft-ui-xaml-winui3-release-2.3.1`：

- `src/dxaml/xcp/dxaml/lib/AutoSuggestBox_Partial.cpp`：150ms timer（47）、文本来源与用户查询（451–507）、focus 行为（933）、键盘/单项列表/Escape/Tab（993–1163）、最大高度与可见性（1251–1318）、先发事件再处理新数据（2274–2292）、滚动到选中项与 SuggestionChosen（2298–2400）。
- `src/controls/dev/AutoSuggestBox/AutoSuggestBox_themeresources.xaml`：header 与正文分行（238–239）、SuggestionsPopup 内使用 ListView（282–286）。

实现引用这些具体行为；未把本次结果当成整个控件已与 WinUI 完全一致的证明。

## 修改

- 用 NSScrollView 和独立 document view 承载行，按稳定 ID 保留行及选择。键盘移动使选中行完整进入视口；普通刷新保留手动滚动位置，尺寸改变重新确保选择可见。
- 将原查询、候选预览、绑定同步和弹窗关闭状态分开处理。Escape/Tab 同步恢复查询；关闭的列表不接受 Up/Down 导航；单个候选不循环取消选择。
- 共享文本绑定 coordinator 增加内部的“外部值已实际应用”通知。AutoSuggestBox 据此清除旧候选，包括 IME 组合结束后才应用的外部重置；其他绑定控件默认没有此回调。
- 新增 `onTextChangedEvent`，携带 `.userInput`、`.suggestionChosen`、`.programmaticChange`。保留 string-only callback；实际文本变化仍按 150ms 合并，focus 本身不发事件。先通知应用，再查询 provider；候选预览不使用候选标题重新过滤。
- 更新弹窗高度、位置、屏幕边界及动画 clip；跟随 anchor/窗口移动；窗口关闭、失焦、移除 host 时释放 panel、事件监听和行的操作能力。
- header 留在自身 bounds；采用主题 body/caption 字体，按字体高度容纳内容；RTL 镜像 adornments、文字 inset、行图标和标签。
- 实际回归发现：AppKit 的 control/cell 对齐 setter 都会结束编辑。编辑时仅改 field editor，失焦后再同步 cell，组合输入时延后格式变化。其失败定位保存在 [alignment-regression.log](before/alignment-regression.log)；这是本批实现过程中的回归，不是原始基线输出。
- AppKit 包裹 field editor 的 NSClipView 随 adornments 调整 viewport、minimum size 和滚动原点，防止按钮占用文字区域以及字形上下裁切。候选预览和外部赋值后也同步 editor 对齐。第一轮门禁通过后的截图仍暴露出竖向裁切和预览左对齐，因此继续修复；[中间版几何数据与截图](before/editor-geometry/)保留了该证据。最终探针新增 glyph/viewport 包含关系及编辑焦点检查。
- Gallery 替换为交互示例：滚动列表、预览开关、延时重排、提交和外部重置。覆盖状态仍为 Partial。

行为修正：**最大高度 0 隐藏列表，负数使用可用屏幕空间**。此外，旧 string-only TextChanged callback 现在也接收程序赋值/候选预览造成的真实文本变化；需要只处理输入时使用新 reason 回调。README/CHANGELOG 已说明。

## 验证

- 全套 **304 项测试、0 失败**（新增 16 项），[日志](after/tests.log)。覆盖组合态模拟、原因/事件顺序、原查询恢复、稳定 ID 重排、字段/弹窗身份、RTL 编辑焦点/选区、短文字完整字形与长文字末尾可见性、窗口移动/屏幕翻转、clip 覆盖、关闭行拒绝操作，以及声明式 body 被回调刷新后的状态。
- [原生验证](after/native-validation.log)、[Gallery 构建](after/gallery-build.log)、[Release 门禁](after/quality.log)通过；测试和原生输出检查 AppKit 约束诊断。
- [Release 原始数据](after/results.json)由 [check_results.py](check_results.py)检查 16 个状态：全部 header 留在 bounds，完整文字字形留在编辑 viewport 内、编辑焦点与对齐方向保持，RTL query 按钮在 x=4；20 条候选有滚动视口；最后一条在导航后及重排后仍选中且可见；84→164 高度生效、离 field 2pt、clip 覆盖；清空后无弹窗。
- Gallery 直接示例数仍为 61；AutoSuggestBox 示例在浅色、深色和 RTL 下挂载。

| Release 观察 | 修复前 | 修复后 |
| --- | --- | --- |
| 20 项 / 84pt 候选列表 | 无滚动视口 | 有滚动视口 |
| 导航到第 20 项 | XCTest 可见高度 0；无 AX selected | 选中且完整进入视口 |
| 请求高度改到 164pt | 仍 84pt | 164pt，原 panel 保留 |
| 外部清空后 | 4 个变体均保留弹窗 | 4 个变体均关闭 |
| header 在控件 bounds 内 | 4 个变体均否 | 4 个变体均是 |

最终 28 张 PNG；[人工复核记录及 SHA-256](after/visual-review.txt)。

截图：[修复前 RTL](before/images/light-rtl-open-field.png)、[修复后 RTL](after/images/light-rtl-open-field.png)、
[最后一项](after/images/light-ltr-last-popup.png)、[重排并增高](after/images/dark-rtl-resize-popup.png)。

复现：

```sh
swift test --scratch-path /tmp/fluentkit-repair-tests -Xswiftc -warnings-as-errors --filter AutoSuggest
./audits/2026-10-31/autosuggest-interaction/run.sh /tmp/fluentkit-autosuggest-interaction
```

`AUDIT_USE_EXISTING_BUILD=1` 使用已有 Release 对象，只采集、不要求修复后的断言通过；用于历史基线。
复现原始基线需要检出 `d6855f3` 的框架代码并使用该版 Release 构建。探针仅调用基线也存在的公开 API。

## 尚未验收

这些是 AppKit 原生调用/组合态模拟和当前 macOS 截图，**不是物理键盘延迟、真实中文候选窗操作或 Windows 像素对拍**。
真实 IME、VoiceOver 朗读、触摸、上翻候选顺序的全部 WinUI 变体、应用自定义模板仍需专项核对。
本批仅暴露与检查 AX selection/press，不据此宣称 VoiceOver 验收通过。SplitButton 和其他菜单消费方继续后续打磨。
