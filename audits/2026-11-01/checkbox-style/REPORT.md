# CheckBox 共享样式、按压外观与无障碍复核

基线：`e0232c4`。范围：独立 `FluentCheckBox`、TreeView 绘制的复选框，以及自动样式。原始与中间失败记录均保留；本批没有修改或安装实际 Fluent IME。

## 确认的问题与修改

1. **未选中填充和描边取错资源。** 自动样式原来使用 Button 的 ControlFill；描边还通过 `withAlphaComponent(1)` 清除了原有透明度。现在分别使用 ControlAltFill Secondary/Tertiary/Quarternary/Disabled，以及 StrongStroke Default/Disabled。选中禁用的描边明确取 StrongStroke Disabled；它目前与 AccentFill Disabled 数值相同，但资源语义不同。
2. **圆角和高对比度边框与源码不符。** WinUI `CheckBoxSize=20`、`CheckBoxBorderThickness=1`，`ControlCornerRadius=4`；旧默认样式为 3pt 圆角，高对比度套用了通用 2pt 边框。现保留 20pt 默认大小，改为 4pt / 1pt。框架自定义密度/尺寸继续缩放大小及圆角；本批不改变自定义 monochrome 样式。
3. **高对比度没有完整状态矩阵。** 原样式没有区分选中与半选的 HighContrast 悬停/按压资源。新增配置 `isIndeterminate`，TreeView 传入实际半选状态；自动样式分别解析三态的填充、描边和标记色。新增 presenter 底色字段，默认透明，HighContrast 使用窗口表面。TreeView 按模板的 1pt margin + 1pt border 将该底色限制在内容区域，避免遮盖固定高度行的外框。
4. **拖出仍显示按压。** 独立 CheckBox 把“正在捕获一次按压”直接当成“显示按压状态”。现在只在捕获且指针仍在控件内时显示按压；拖出释放不切换，拖回后释放只切换一次。TreeView 的既有捕获逻辑继续复用相同样式。
5. **显式主题可能拿到另一种系统颜色。** AppKit 动态 NSColor 转 CGColor 时依赖当前绘制外观；事件和绑定回调不一定处于控件自己的外观。自动 CheckBox 样式现先在显式 light/dark 外观中解析系统颜色，随后提供稳定的颜色给图层。
6. **独立 CheckBox 不在外部 AX 树中，值类型也不正确。** 现在明确暴露为可访问元素，getter 返回 NSNumber/Bool，并在值变化时发出通知。外部 AX 查询与点击已验证。Apple 对复选框的返回类型及通知要求见 [accessibilityValue 文档](https://developer.apple.com/documentation/appkit/nsaccessibilitycheckbox/accessibilityvalue%28%29?language=objc)。此项不等于完整 VoiceOver 验收。

## 对照依据

本地固定版本 `microsoft-ui-xaml-winui3-release-2.3.1`：

- `src/controls/dev/CommonStyles/CheckBox_themeresources.xaml`：三套主题的 CheckBox 资源别名、20pt 大小、1pt 边框、RootGrid 和 NormalRectangle。
- `src/controls/dev/CommonStyles/Common_themeresources_any.xaml`：ControlAltFill、StrongStroke 与 TextOnAccent 的色值/透明度。
- `src/controls/dev/CommonStyles/CornerRadius_themeresources.xaml`：三套主题的 ControlCornerRadius 都是 4。
- `src/controls/dev/TreeView/TreeViewItem.xaml:131` 及 `TreeView_themeresources.xaml`：MultiSelectGrid 的高对比度 margin/border，以及内部 32pt × MinHeight 28pt 的 CheckBox。

资源别名和来源哈希保存在 `winui-resource-aliases.json`。HighContrast 是**资源角色移植**：ButtonFace / ButtonText / Highlight / HighlightText / GrayText 使用 AppKit 相应系统颜色，Window 使用 Fluent 窗口表面，与既有 RadioButton 策略一致。它不声称复刻某一套 Windows 对比度主题的实际调色板。

## 验证与证据

| 检查 | 修复前 | 修复后 |
| --- | --- | --- |
| 完全相同的 6 项回归用例 | 在独立 `e0232c4` 工作树运行，230 处断言失败 | 0 失败 |
| 原生颜色/尺寸采样 | 100 个采样，391 个字段不符 | 100 个采样，0 个字段不符 |
| 外部 AX 查询 | 看不到 CheckBox | 显示 checkbox，值 off → on → off |
| 全量单元测试 | 407 项既有基线 | 413 项，0 失败 |
| 原生验证 | 旧断言要求粗边框和字符串值 | 已依据上述源码/平台协议更新；PASS |
| Gallery Xcode 构建 | — | Debug 构建成功 |
| Release 质量门禁 | — | 更新计数、挂载身份、外部重置、字体/材质及 Gallery 样例门禁通过；见 `after/quality-run.log` 和 `after/quality/` |

“100 个采样”包含取消后复测，并非 100 个互不重复的状态。覆盖 light/dark × standard/high contrast × 普通/悬停/按下/拖出/禁用；TreeView 没有本批可用的禁用 API，最后一阶段只复测取消后的普通状态，明确不算 TreeView 禁用验收。独立 CheckBox 仍是 Bool 控件；半选由实际 TreeView 的父/子选择生成。

颜色判定来自独立转录的 WinUI 资源矩阵；未选中颜色直接使用源码 ARGB。Accent 与 TextOnAccent 的通用调色板解析继续使用 Theme，本批重点检验 CheckBox 选取的资源角色。渲染记录由真实控件图层获得，不是只调用样式返回值；最终 before/after 均链接 Release 产品。固定高度高对比度行的底色裁切还做了图像检查和布局断言。

关键文件：

- `before/tests-final-cases.log` 与 `before/BaselineResourceTests.swift`：旧提交上的最终同一组用例。其 SHA-256 与仓库最终测试一致，见 `before/provenance.json`、`after/provenance.json`。独立基线工作树已移除，构建缓存保留。
- `after/tests-focused-final.log`、`after/tests-all.log`、`after/test-diagnostics.log`：修复后的集中/全量用例及诊断扫描。
- `before/native/`、`after/native/`：每边 20 张原生图层图、100 条记录；`comparison.json` 是逐字段差异。
- `after/native-validation.log`、`after/gallery-build-final.log`：原生验证及 Gallery 构建。
- `after/interactive/AX-REVIEW.md`：实际外部 AX 操作与坐标输入限制。

初始探针的事件构造错误、编译错误和未正确布置 TreeView 宿主的图像分别保存在 `before/harness-*`、`before/incomplete-render/`；它们是验证工具问题，不计入框架缺陷。首次修复的高对比度底色遮住行边框，保存在 `after/intermediate-render/`，已通过内容区域裁切修正。两个过时的原生验证断言失败日志也保留，没有把改断言当成独立修复证据。

## 复现

```sh
swift test --scratch-path /tmp/fluentkit-repair-tests -Xswiftc -warnings-as-errors --filter CheckBoxResourceTests
swift build --target FluentKit -c release --scratch-path "$TMPDIR/fluentkit-quality-release" -Xswiftc -warnings-as-errors
zsh audits/2026-11-01/checkbox-style/run-probe.sh after
python3 audits/2026-11-01/checkbox-style/check-results.py
zsh tools/run-quality-checks.sh /tmp/fluentkit-checkbox-quality
```

`run-probe.sh` 链接已有产品，故运行 `before` 时必须显式指向旧版本产品；它不会自动恢复旧源码。`FLUENTKIT_CHECKBOX_PRODUCTS` 可指定产品目录。脚本同时生成 `/tmp/Fluent CheckBox before.app` 或 `after.app`，正常打开可进行隔离交互；不会触及安装中的 IME。

## 保留的边界与下一步

- CUA 对隔离窗口的坐标拖动/带时长点击返回 `AXError.notImplemented`，没有生成目标 CheckBox 的原生拖动事件。拖出/重入结果来自直接投递 NSEvent 的原生测试和图层记录；外部点击只计入 AX 动作，不计为物理鼠标/触屏。
- 没有新增独立 CheckBox 三态绑定或动画资源；TreeView 的半选图形与现有选择动画继续使用现有实现。WinUI AnimatedIcon 的逐帧形变、键盘按下/释放节奏、Windows 同 DPI 像素对照、完整 HighContrast 行布局、真实 VoiceOver 仍需后续验收。
- RadioButton 等同源控件还存在返回 On/Off 字符串的代码路径，下一批独立核对其 AX 暴露和显式高对比度颜色，不能将本批结果推广到它们。
- 实际 IMK 候选定位、完整 TreeView 原生拖放、其他原审计长尾继续保留在 `../FOLLOW-UP.md`，本批不关闭这些项目。
