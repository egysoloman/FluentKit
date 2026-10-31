# 导航和撤销作用域重放旧内容

基线 `addf1b2`。本项是实际 Gallery 验收中发现的前置阻碍：侧栏和历史状态已经改变，正文仍显示主页，无法进入用户报告的折叠卡。

## 独立复现

`FluentNavigationHistoryScopeView` 和 `FluentUndoScopeView` 在 mount 时把当时的 content 存进 updateContent 闭包；后续 `_updateView` 调用旧闭包，没有使用这次声明式更新提供的新 content。

结果不仅是文本不变：动作闭包也保留旧值；同一个 FluentAnyView 从文本换成其他原生控件时，包装层仍更新旧文本。4 个新增回归测试产生 8 个失败断言，见 `before/tests.log`。测试同时检查原生身份、父视图不变与 Undo 环境传递。

`ScopeGalleryAudit.swift` 挂载实际 `FluentAnyView(GalleryScreen(...))`，通过其导航协调器依次请求 Button、Expander、CheckBox，再后退/前进。每步等待动画完成，检查实际正文标签和 Expander 控件存在性，并直接渲染图层。浅/深色各 6 个状态，包含初始主页。

| 检查 | 修复前 | 修复后 |
| --- | ---: | ---: |
| 正确呈现请求页面的导航状态 | 0 / 10 | 10 / 10 |
| 进入或返回 Expander 时存在的内层 Expander | 0 | 2 |

前后实际 Gallery 源码 SHA-256 相同，基线探针明确链接保存的旧 FluentKit.o（哈希见 `before/library-sha256.txt`）。原始 JSON、12 张基线和 12 张修复后图片分别保留。人工检查修复后的实际 Expander 页面，确认不是只有侧栏选中项发生变化。

## 修复和边界

两个包装层的更新直接调用当前 content，移除不再需要的旧更新闭包。Undo 更新继续把本作用域的 coordinator 放进子环境；导航继续更新 onNavigate。协调器身份不变且原生类型兼容时保留原生实例；内容类型不兼容仍通过现有返回 false 协议重建该分支。

没有改变历史栈、撤销栈、快捷键规则或页面动画参数。这是包装层的声明式更新契约修复，不把它描述成某一 Windows 动画效果的复刻。

- 全量 **370 项测试**通过，构建 warnings-as-errors；无 AppKit 约束诊断。
- 原生 FluentKitValidation、Gallery Xcode Debug 构建、Release 质量门禁通过。
- 实际 Gallery 10 个导航状态通过，包含前进/后退和不同样例类型。

这使后续折叠卡布局验收成为可能，**没有关闭折叠卡的动态测量问题**。其他包装层中仍存在类似缓存更新闭包的模式，需要分别复核，不凭文本模式推定全部有缺陷；作为主题/生命周期后续检查保留。快速切页、动画中缩放和真实输入法窗口仍按既有计划继续。

复跑：`./audits/2026-11-01/scope-refresh/run.sh /tmp/fluentkit-scope-refresh-new`。需要比较指定旧库时可用 `FLUENTKIT_SCOPE_LIBRARY`，应同时记录对应源码提交和对象哈希；不覆盖本目录历史数据。
