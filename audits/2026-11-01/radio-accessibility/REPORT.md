# RadioButton：分组、可访问性与显式主题

本批基线为 `c5ad3bd`。独立复现了普通 NSView 中的互斥失效、不同父级意外合组、AX 暴露/值类型不符，以及高对比度事件刷新使用错误外观。修复保留声明式 RadioButtons 已有的选择协调器。

## 依据与根因

- 本仓库固定的 WinUI 源码 `microsoft-ui-xaml-winui3-release-2.3.1/src/dxaml/xcp/dxaml/lib/RadioButton_Partial.cpp`，`GetGroupName` / `GetParentForGroup`：未命名组以直接父级为范围，命名组以视觉根为范围，名字按完整字符串匹配。旧实现固定跨过一层父级，又将任意只有一个子视图的 NSView 当作包装器：同一父级内的按钮可能找不到彼此，不同父级反而可能互斥。
- `src/controls/dev/CommonStyles/RadioButton_themeresources.xaml` 的 HighContrast 资源：标签采用 ButtonText/GrayText，圆点、外圈及填充分别按状态取资源。旧实现让动态 NSColor 在转 CGColor 时使用当前绘图外观；事件回调中的外观不一定等于显式 Fluent 主题。标签还一直使用普通 TextFill。提取结果和源码 SHA-256 见 `winui-resources.json`。
- [Apple NSAccessibilityRadioButton.accessibilityValue](https://developer.apple.com/documentation/appkit/nsaccessibilityradiobutton/accessibilityvalue%28%29) 要求 NSNumber 布尔值和状态变化通知。旧独立控件未设置 `isAccessibilityElement`，返回 `"On"/"Off"` 字符串；声明式组的三个子项已经可以通过 AX 操作，但组容器被省略。不能将旧情况描述为“所有 RadioButton 均不可访问”。

## 修改

- 无名组使用直接父级，只透明穿过已知的 `FluentBoundRadioButton` 绑定适配器；任意单子视图 NSView 保持真实组边界。命名组仍可跨父级互斥。**行为变化：组名不再自动去掉首尾空白**，`" scoped "` 和 `"scoped"` 是不同组。
- 独立 RadioButton 和声明式组显式暴露 AX 元素；单选值为 NSNumber，选择变化发送 `.valueChanged`。重复激活已选项不清空，不重复发布选择；禁用项拒绝激活。
- 默认 RadioButton 样式在显式主题外观下解析 HighContrast 系统颜色，标签改用相应系统文字角色。解析帮助函数与 CheckBox 共用；CheckBox 资源行为保持不变。
- 原生验证同步检查公开 AX 元素及数字值。已有测试原本比较动态 NSColor 对象身份，现改为在明确外观下比较实际 RGB 颜色。

## 修复前后证据

| 验证 | 基线 | 修复后 |
| --- | --- | --- |
| 同一组 5 项新增测试 | 162 处断言失败 | 全过 |
| 112 个独立原生状态，按字段与资源/几何预期比较 | 48 个状态有 156 项字段偏差 | 0 项偏差 |
| 外部 AX 查找独立 A1/A2/B1 | 三项均不在 AX 树中 | 三项均可查询 |
| 选择同组 A2 | A1=true、A2=true | A1=false、A2=true |
| 独立父级 B1 | true | 仍为 true |
| 声明式组 | 子项可用，组容器缺失 | 带标题容器及子项均可查询 |
| 声明式模型更新 | Manual 选择正常，作为正向对照 | Manual 选择、外部 nil 清空均正常 |

5 项新增测试还覆盖：不同单子视图父级隔离、绑定适配器透明、跨父级命名组、含空白组名、原生兄弟的方向键循环/跳过禁用项、标签/填充/描边/圆点的显式主题颜色。最初版本为 161 处失败；补充空白组名断言后，在仍未修改运行时代码的同一基线重跑得到 162，两个日志均保留，最终测试副本在 `before/BaselineRadioButtonTests.swift`。

原生矩阵为 2 种深浅色 × 2 种对比度 × LTR/RTL × 选中/未选中 × 7 个阶段（正常、悬停、按下、拖出、重入、外侧释放取消、禁用）。事件更新刻意置于相反的 NSAppearance。`comparison.json` 保存逐字段结果；`before/native`、`after/native` 各保存 112 条 JSON 记录及 112 张 2× layer 渲染图。下图为暗色、高对比度、RTL、选中按下态：

![修复前](before/native/dark-high-rtl-pressed-selected.png)
![修复后](after/native/dark-high-rtl-pressed-selected.png)

**探针纠错记录：** 第一版在同一窗口依次按住两个按钮，后一个取得焦点会取消前一个，导致前一个的“按下/拖出”等标签不再对应实际状态。没有据此改运行时代码。已保留 `RadioAudit-first-pass.swift`、两侧 `native-first-pass`、对应日志和 `comparison-first-pass.json`；最终改为每个窗口只测一个按钮，并从独立 `c5ad3bd` 工作树重建 Release，再用同一个新探针重采两侧。表中的数字只来自最终采样。

外部 AX 操作使用 CUA。旧版通过辅助按钮触发 A2 的同一 AXPress 方法，复现双选；新版直接点击已暴露的 A2，再点击声明式 Manual 与 Clear model。状态由原生应用自行保存到两侧 `interactive/selection-events.json`，AX 树观察摘录在 `cua-observations.json`。这是 AX 查询/激活验证，不是物理鼠标或 VoiceOver 播报验收。

## 门禁与复现

修复后 418 项测试、原生 `FluentKitValidation`、Gallery Xcode 构建、Release 质量门禁均通过；测试日志未发现 AppKit 约束诊断。日志及门禁原始数据均在 `after/`。源文件、最终测试与探针哈希在两侧 `provenance.json`，基线静态库哈希也已保存。

```sh
swift test --scratch-path /tmp/fluentkit-repair-tests -Xswiftc -warnings-as-errors --filter RadioButtonAuditTests
swift build --target FluentKit -c release --scratch-path "$TMPDIR/fluentkit-quality-release" -Xswiftc -warnings-as-errors
zsh audits/2026-11-01/radio-accessibility/run-probe.sh after
python3 audits/2026-11-01/radio-accessibility/check-results.py
```

重跑探针会写入对应阶段目录，保留历史证据时请在另一个 checkout 执行。采集旧版需要先在 `c5ad3bd` 构建 FluentKit，并通过 `FLUENTKIT_RADIO_PRODUCTS` 指向该 Release 产品目录。两个阶段使用相同探针。`sandbox_extension_issue_file_to_process` 出现在临时应用的 stderr，但进程成功结束并输出完整 112 条记录；不将其隐藏为没有环境诊断。

## 仍开放的范围

- 高对比度采用当前移植层的 AppKit 系统颜色映射，不代表 Windows 高对比度调色板的逐像素一致。Windows 字形、缩放、动画时序及真实 VoiceOver/触摸仍需专项验收。
- WinUI CheckGlyph 还有内圆描边/渐变及多个 VisualStateGroup 的共同作用；当前单个填充 CALayer 尚未完整对齐，不能把本批颜色检查当作整个 RadioButton 模板完成。
- 原生兄弟移除/改组后的组位置描述，以及绑定变化与正在进行的指针/Space 手势交错，需要继续专测；本批没有据源码推断直接宣称已验证或修好。
- 未安装、替换或停止正在运行的 Fluent IME。实际 IMK 候选位置等原任务仍见 `../FOLLOW-UP.md`。
