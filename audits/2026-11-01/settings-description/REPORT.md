# 设置卡说明文字在缩放后截断

2026-11-01；跟进队列第 28 项。Gallery 原始基线为已发布的 `v0.2.0` / `1c0fa09`，修复前测试基线为 `3b52545`（此期间 Settings 实现相同）。

## 独立复现

使用实际 Gallery 源码挂载 Expander 页面，保留开合、快速反向、宽→窄→宽与深浅色共 24 个窗口状态。两个 narrow 状态中，说明文字需要 30pt，但只分到 20pt，缓存的 intrinsic height 仍为 15pt；卡片保持 64pt。截图末尾缺少 `acceptance matrix`，原始数据为 `before-gallery.json`、`before-images/` 和 `baseline-metadata.json`。

单独约束宽度的 primitive 对照可以正确换行，见 `ConstrainedControl.swift` 与 `constrained-control.json`。首个滚动测试夹具让 NSWindow 自动增大到最小宽度，不能据此判定窄窗口溢出；该失败记录保存在 `first-fixture-tests.log`。固定宿主宽度后，测试复现两个卡片说明的实际裁切及未增长高度，共 4 个失败断言（`before-tests.log`）。

## 根因与实现

NSTextField 的换行测量没有收到最终可用宽度。Apple 的 [preferredMaxLayoutWidth 文档](https://developer.apple.com/documentation/appkit/nstextfield/preferredmaxlayoutwidth) 说明，换行字段的 intrinsic height 会按这个宽度计算；默认 0 表示不指定最大宽度。

在卡片 `layout()` 读取子 stack 的 bounds 会拿到上一次尺寸：第一个候选修复的 Gallery 数据显示窄窗口仍使用 718pt，下一次变宽反而使用 418pt。该方案已撤回，结果保存在 `first-fix-*`。

最终通过私有标签 stack 的实际 frame 宽度变化更新测量宽度，并考虑 NSTextField 的 alignment insets。高度变化向祖先失效传播，由 Auto Layout 正常完成重新排布；不会在分配子视图 frame 过程中强制递归 layout。使用可用容器宽度而非上一轮文字实际宽度，保证窗口放宽后能恢复。既有最多两行、64pt 最小卡片高度和公开 API 保持原契约。

## 验证

两项新增回归覆盖滚动容器的宽→窄→宽、普通卡与折叠卡、同实例修改说明、隐藏/恢复、尾部 action 增宽、LTR/RTL 及后续行位置。相关 11 项通过；完整 **502 项测试、0 失败**，无 AppKit 约束诊断。全产品 Release、Xcode Gallery 构建成功；原生验证 PASS。

实际 Gallery 的 Debug 探针已确认深浅色窄窗口均恢复为 header 74pt / description 30pt；宽窗口及恢复状态为 64pt / 15pt。截图已检查第二行完整出现，后续正文跟随下移。

最终 Release 更新计数、挂载身份、外部重置、字体和材质门禁全部通过（`quality/`）；Release 链接的实际 Gallery 24 个状态同样通过，说明文字截断从 2 处归零，原有 Expander 几何门禁亦通过。原始数据和截图为 `gallery-final/`，执行记录为 `final-gallery-run.log`，无 AppKit 约束诊断。

复现：`zsh run-gallery.sh <SwiftPM products 目录> <新输出目录>`。兼容两种 SwiftPM 产物布局，保存对象与源文件摘要，检查原有 Expander 几何以及说明文字空间。`check_results.py before-gallery.json` 必须失败并报告两处截断。这里是实际 AppKit 窗口与 Gallery 页面代码的自动化渲染结果，不代替 Windows 像素对拍及真实硬件验收。
