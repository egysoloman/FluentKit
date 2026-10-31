# Gallery 嵌套折叠卡布局修复与实际页面复验

基线 `f308a9e`，已先修复阻止 Gallery 正文切换的导航/Undo scope 问题。原始失败证据保留在 `before/`。本批修复嵌套高度、明确宽度被撑破，以及 Gallery 示例在窄窗口下撑宽页面三个问题。

## 实际 Gallery 复现

`ExpanderGalleryAudit.swift` 直接挂载 GalleryScreen，通过导航进入 Expander 页面，操作真实外层 Interactive sample 设置折叠卡和两个内层 Expander。使用控件的无障碍激活动作触发业务行为，等待动画完成并记录布局；这不是 VoiceOver 操作验收。

浅/深色各记录 12 个状态：初始、收起早期帧、收起下方展开器、收起两个内层、重新展开下方、关闭/重开外层、展开上方、820/1400/1120pt 宽度及快速反向操作。原始坐标和图像在 `before/`，共 24 个状态；无 AppKit 约束诊断，但仍存在可见布局错误。

| 状态 | 外层内容区高度 | 内容实际所需高度 | 问题 |
| --- | ---: | ---: | --- |
| 初始两个内层均展开 | 282pt | 282pt | 初始正确 |
| 两个内层均收起 | 282pt | 184pt | 多出 98pt 空白，外层及下方内容没有同步上移 |
| 重新打开外层后，再展开上方内层 | 233pt | 282pt | 少 49pt，内容被裁切 |
| 后续缩窄、拉宽、恢复 | 233pt | 282pt | 调整窗口尺寸不能修复旧高度 |

上述数值为浅色；两种主题的原始汇总分别见 `before/summary.json`。第二个独立问题：第一个内层 Expander 的实际宽度为 **549pt**，其 `.frame(width: 520)` 父容器为 **520pt**，横向越界 **29pt**。

## 源码定位

1. `FluentSettingsExpanderHost` 用固定 contentHeight 约束保存展开时测量值，只在自身展开/收起时更新。内层控件的布局失效虽然向祖先传递，但该常量没有随内容重新测量。仅在外层关闭后再打开才暂时正确。
2. `FluentExpanderHost` 把内容的自然宽度作为 intrinsic width，并设置 required 水平抗压缩优先级。外层 `.frame` 和布局边界为 999；自然宽度 549 因此压过 520 的布局槽，子视图越过父容器的尾边界。

对照：本地 WinUI `src/controls/dev/Expander/Expander.xaml` 使用 Grid/ContentPresenter 参与常规测量，展开/收起改变内容 Visibility；Gallery 的 `WinUIGallery/Samples/Expander/ExpanderPage.xaml` 明确示范固定 Width 和内容对齐。FluentKit 的 SettingsExpander 是自己的组合表面，不能假称有一份完全相同的 WinUI 控件模板；但它必须随嵌套内容更新布局。

## 实现及结果

稳定展开时，外层设置卡改由内容上下边界决定高度；固定高度约束仅用于自身折叠动画和收起状态。动画完成或被外观切换打断后恢复自然测量，使用当前内容，不冻结动画开始时的旧目标。测量函数不再递归触发自己的布局。

普通 Expander 的自然宽度恢复为可压缩的测量偏好；垂直栈填宽不再把子视图的抗压缩优先级强制提高到 required。默认自然最小宽度 320pt 和 48pt 头部度量保留，显式尺寸与布局边界仍用原有优先级，未增加 520pt 特判。

同一 Gallery 源码的 24 个前后状态：

| 指标 | 修复前 | 框架修复后 |
| --- | ---: | ---: |
| 内层全部收起后的多余高度 | 98pt | 0pt |
| 重开外层、再展开内层后的缺失高度 | 49pt | 0pt |
| 固定 520pt 内层的实际宽度 | 549pt | 520pt |

`after/` 是**只更新框架、尚未调整 Gallery 示例**的结果，源码哈希可核对。该轮也暴露第三项：820pt 窗口下，固定 520pt 的示例加上内边距需要 600pt，但外层只有 491pt 可用，整页被撑出可视区。Gallery 两个示例因此改为随所在行伸缩。`responsive-after/` 保留另一次 24 状态复验：窄窗口外层 491pt、内层 411pt，卡片右边界、箭头和圆角恢复可见。固定尺寸 API 仍由单独回归测试覆盖；这项示例调整不是把框架的宽度错误隐藏起来。

`ExpanderLayoutTests.swift` 新增 6 项测试，覆盖嵌套上下展开 × LTR/RTL、Reduce Motion、下方兄弟位置、内容替换、随宽度换行的高度、动画中改变内容和尺寸、快速反向操作，以及明确宽度/填满整行。将同一最终测试放到隔离的 `572628d` 基线运行，得到 **15 个失败断言**；修复后全过。

初次填宽测试没有限制窗口本身，AppKit 扩宽窗口后使测试的期望值不成立。最终测试通过明确分配的布局槽验证，已在旧基线上重跑；两份 `initial-tests.log` 仅保留探索过程，不作为最终结论。

## 背景与折叠的联合验收

`ExpanderSurfaceAudit.swift` 按 Gallery App 的窗口配置、背景与主题协调器装配真实 GalleryScreen。浅/深色 × 材质开/关，记录放大、缩窄、真正导航到 Expander、内外层折叠、打开过程中改变内容和窗口尺寸及恢复窗口，共 **100 个状态**。16 个切页状态均实际包含两个 Expander，避免此前“侧栏变了但正文没变”的误判。

最终 `surface-responsive/` 的 **200 个染色层/遮罩采样**没有额外动画，模型与 presentation 几何偏差均为 0。内层收起时，下方 Source identity 行上移 98pt、滚动文档缩短 98pt；关闭外层后内容隐藏，重开并缩放后恢复显示。`surface-after/` 是示例调整之前的独立集成记录，两套数据均保留。

自动检查由 `check_results.py` 完成：24 状态检查展开高度、子视图宽度和卡片可见边界；100 状态检查真实页内容、背景几何、兄弟位置和滚动范围。截图使用真实 layer tree 的 presentation 渲染，已人工检查深色的收起和窄窗口状态。

最终全量 **376 项测试**、原生验证、Gallery Xcode 构建和 Release 质量门禁通过，无 AppKit 约束诊断。`quality-after/` 保存门禁结果。这些结果证明本批布局和背景路径恢复，不等同于 Windows 像素对拍、真实触摸或 VoiceOver 验收；搜索、候选浮层、翻页和系统主题问题继续按 `../FOLLOW-UP.md` 推进。

复跑（输出使用新目录）：

```sh
./audits/2026-11-01/expander-layout/run.sh /tmp/fluentkit-expander-layout-new
./audits/2026-11-01/expander-layout/run-surface.sh /tmp/fluentkit-expander-surface-new
```

首次探索误向 NSButton 头部调用无障碍动作，断言失败；最终驱动使用 Expander 自己公开的无障碍激活入口并正常完成，这不是产品运行时崩溃证据。无障碍激活动作也不代替 VoiceOver 操作验收。
