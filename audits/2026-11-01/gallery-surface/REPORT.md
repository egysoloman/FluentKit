# Gallery 窗口壳背景缩放的第二处缺陷

基线 `fa357e4` 已包含 IME 材质背景修复。本批在其上独立复现 Gallery 的背景分界；不是重复宣称上一项已经覆盖所有宿主。

## 根因

`FluentWindowSharedChromeHost` 自己还有 SharedChromeTint 及 even-odd 裁切遮罩。它们不是 FluentMaterialView 内部的 fallback/tint 层，旧 `layout()` 和内容区域通知路径仍直接修改 frame。在窗口 zoom 的动画事务中，两层都额外启动 bounds/position 动画。

实际 GalleryScreen 放大到 1512×884pt 时，深色材质场景的染色层和遮罩 presentation 仍约为 1132×764pt，截图可见顶部右侧及侧栏底部的色块分界。页面 ContentSurfaceClip 本身没有滞后，上一批修过的材质层也已同步。

现在通过同一个无隐式动作的事务提交染色层与遮罩的几何。内容区域独立通知也走同一路径，避免只修父层 layout 漏掉遮罩更新。颜色、窗口激活时的透明度、页面转场及材质选择策略不变。

## 复现和结果

`GallerySurfaceAudit.swift` 直接编译实际 GalleryScreen 和样例源码；窗口配置、背景绘制、主题协调器和宿主约束按 App.swift 装配。驱动有独立进程和窗口，不操作用户正在运行的 Gallery。

浅/深色 × 材质开/关，分别采集初始、zoom、缩窄、导航请求和恢复尺寸的中间帧，共 68 个状态。模型与 presentation 几何见两侧 `results.json`；前后 Gallery 源码哈希一致。

| 指标 | 修复前 | 修复后 |
| --- | ---: | ---: |
| 染色层/遮罩采样 | 136 | 136 |
| 有额外几何动画的采样 | 60 | 0 |
| 宽度最大偏差 | 691.40pt | 0pt |
| 高度最大偏差 | 323.72pt | 0pt |

材质关闭时染色层隐藏；其几何仍被检查，但不把隐藏层的差异描述为可见色块。四组初始渲染的完整 RGBA 像素前后相同，缩放中的分界消失。已检查深色材质 zoom 中间帧；图片与汇总保存在 `before/images`、`after/images`、`after/comparison.json`。

回归用例覆盖浅/深色 × LTR/RTL × 扩大/缩小，修复前 32 个断言失败；修复后通过，并检查内容区中心始终落在染色遮罩的挖空区域中。全量 **366 项测试**、原生验证、Gallery Xcode 构建及 Release 质量门禁通过，无 AppKit 约束诊断。

## 验收中发现的另一个问题

`page-*` 表示发起了导航请求，**不是成功切换到 Expander 的证据**。人工检查截图发现侧栏已选 All controls，但正文仍是主页。导航和 Undo scope 的更新代码仍执行 mount 时捕获的旧 content。该项另立 `scope-refresh` 复现，需先修复才能继续实际 Gallery 折叠卡和切页验收；本批不混入这个运行时改动。

因此，本批证明 Gallery 窗口壳几何同步缺陷已修，不能宣称所有切页背景、折叠卡布局或主题传播问题已关闭。该记录也再次说明有状态名称和通过的几何检查不代表实际画面已达到目标页面。

复跑：`./audits/2026-11-01/gallery-surface/run.sh /tmp/fluentkit-gallery-surface-new`。原始 before/after 不覆盖；不是 Windows 像素对拍或物理触摸验收。
