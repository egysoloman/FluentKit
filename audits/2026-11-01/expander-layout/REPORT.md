# Gallery 嵌套折叠卡布局：已复现，待修复

基线 `f308a9e`，已先修复阻止 Gallery 正文切换的导航/Undo scope 问题。本目录当前只有**修复前证据**，不代表布局问题已经解决。

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

## 下一步实现及验收

- 让外层在稳定展开状态使用内容的自然布局关系，固定高度仅承担自身折叠动画/收起状态；验证内层高度变化、宽度相关测量、内容替换及动画打断，不以反复关开作为修复。
- 修正内层自然宽度与明确分配尺寸之间的优先级关系，同时检查垂直栈的填宽策略。保留源码最低尺寸语义，避免为了 520pt 个例引入一个新的硬编码宽度。
- 添加有失败基线的动态几何回归；复跑同一实际 Gallery 驱动，检查外层高度、内层边界、下方兄弟和滚动范围；扩展 RTL/Reduce Motion 与中间帧。
- 在运行时修复完成后再运行相关门禁并分批提交，不把当前 370 项既有测试通过作为本项关闭依据。

复跑：`./audits/2026-11-01/expander-layout/run.sh /tmp/fluentkit-expander-layout-new`。默认不覆盖历史记录。首次探索误向 NSButton 头部调用无障碍动作，断言失败；最终驱动使用 Expander 自己公开的无障碍激活入口并正常完成，这不是产品运行时崩溃证据。
