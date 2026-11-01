# ComboBox 浮层工作区尺寸与实时重测

基线：`f0ef72e9b2357e36b6ae9c716c8f7e26dbaae095`。本批接续多屏队列第 22 项；不表示物理双屏已经验收。

## 独立复现

1. `before-tests.log`：两条旧运行时回归、5 个失败断言。在 1512pt 宽的真实内置屏幕上，重复长选项使浮层宽 **6206pt**；LTR 和 RTL 都越界。打开后把宿主从 220pt 加宽到 600pt，再触发窗口 resize 通知，浮层仍宽 **220pt**。原始测试源码保存在 `BeforeTests.swift.txt`，基线源码哈希见 `baseline-source.txt`。
2. `ComboWorkAreaAudit.swift` 使用公开 `FluentComboBox` API，链接修复前 Release 对象（`before/source-sha256.txt`）；在浅/深色 × LTR/RTL × 长标题/动态加宽 × 打开/加宽后共 **16 状态**检查实际 NSPanel。`before/results.json` 中 **8 状态越出屏幕，4 状态未覆盖加宽的 faceplate**。渲染只合成探针自身的窗口和浮层图层，画布是屏幕工作区；黑色空白不是桌面截图。
3. 较小工作区不改变系统分辨率：纯尺寸计算使用合成工作区；原生视图测试把 380×220pt 工作区交给生产 `updateLayout(in:)`，检查实际滚动视口、行和焦点。它不等价于物理跨屏/分辨率切换。

## WinUI 对照

参考仓库内 `microsoft-ui-xaml-winui3-release-2.3.1/src/dxaml/xcp/dxaml/lib/ComboBox_Partial.cpp`：

- `GetNonPannablePopupLayout`（约 4766–4910）：可用高度影响呈现范围和滚动偏移。
- `ArrangePopup`（约 5320–5440）：内容宽度限制为可用范围；faceplate 的 MinWidth 仍优先；设置 popup MaxWidth/MaxHeight。

因此本批约束内容测量、按整行减少视口，保留现有 4pt 工作区边距。如果 faceplate 自身跨屏且宽过工作区，仍按 WinUI 的明确 MinWidth 规则保留其宽度，不能声称这种情况也完全收进单屏。

## 修复

- 最长标题只在呈现或主题改变时测量，窗口移动/缩放通知不会反复遍历字符串。
- 浮层宽度限制到目标工作区，且实时跟随 faceplate 的最小宽度；高度限制到可用整行数，滚动文档保留全部选项。
- 初次受限时，显示范围包含选中项。已打开面板重排保留面板、内容和 first responder；缩小时保留正在看的选中行或键盘焦点行，放宽后恢复尺寸。
- 滚动条按实际视口更新；调整动画宿主的 reveal clip，防止面板变宽后仍被旧尺寸裁切。
- 本批不改默认开启范围的既有选择策略；WinUI 完整 non-pannable 填充顺序、touch pannable 的循环/半行策略、编辑模式极小工作区的完整摆放策略仍需单独对照。

## 验证

上一批 `f0ef72e` 的 [CI #16](https://github.com/egysoloman/FluentKit/actions/runs/41289877868) 已完成成功：512 项测试、1 项平台能力跳过、0 失败，所有作业步骤通过。日志保存在 `previous-batch-ci.log`。这份 CI 日志验证上一批选屏修复，本批 ComboBox 的远端验证将在推送后运行。

- 相关 **19 项测试通过**；完整 **516 项、0 失败**，78.337 秒（`targeted-tests.log`、`full-tests.log`）。
- Release 构建通过，103.34 秒；Gallery 的 Xcode 构建通过（`release-build.log`、`gallery-build.log`）。
- 原生验证 PASS，Release 更新次数、挂载身份、外部重置、字号/材质门禁全部通过（`native-validation.log`、`quality.log`、`quality/`）。诊断检查没有 AppKit 约束冲突。
- 修复后同一公开 API 的 Release 探针 **16 状态、0 失败**（`after-check.json`），原先 8 处越界和 4 处宽度不足归零；所有状态保留面板/内容/响应者身份和模型。图片人工检查确认 220→600pt 的内容及遮罩同步变宽，长选项浮层收进工作区；保留前后全部 32 张图。

复现命令（输出目录必须新建）：

```sh
zsh audits/2026-11-01/combobox-workarea/run-native.sh <SwiftPM-products> <output-dir>
python3 audits/2026-11-01/combobox-workarea/check_native.py <output-dir>/results.json
swift test --scratch-path /tmp/fluentkit-repair-tests -Xswiftc -warnings-as-errors --filter ComboBoxWorkAreaTests
```

未安装、替换或停止 Fluent IME，也未切换系统显示模式。物理多屏、混合倍率、热插拔、真实输入法和 VoiceOver 仍保留专项验收。
