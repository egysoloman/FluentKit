# TreeView 接手复核、生命周期修复与 Gallery 验证

日期：2026-10-31。基线：`be4e31a`。接手时 `git status --short` 为空。

## 结论与范围

先补跑了交接记录中缺少的两项：原基线的 Release 质量门禁及 Gallery Xcode 构建均通过，原始结果见 [before](before/)。随后独立复核 TreeView 的更新、绑定、选择、RTL 和实际 Gallery 交互，发现并修复下列问题。通过原有门禁并不能排除这些缺陷。

本轮保留原 TreeView 架构和公开 API，增加一个直接示例；没有把 TreeView 从 Partial 升为已完全实现。本报告不代表对交接中的全部提交做了穷尽审查，也不替代 Windows 像素、真实触摸、IME 或 VoiceOver 验收。

## 独立发现及修复

| 问题 | 修复前证据 | 本轮处理 |
| --- | --- | --- |
| 不变树重复重建节点并 `reloadData()` | 3 行内容连续 5 次更新，原生内容产生 **15 次 `viewDidMoveToSuperview`**，节点和 cell 身份改变 | 按稳定 ID 复用节点；只在根顺序、子节点结构或延迟加载标记改变时 reload；同场景回调 **0 次**，节点/cell 保持身份 |
| 未绑定的单选在重排后丢失 | 选中 b，再把 a,b,c 改为 c,a,b，选中行变为 -1 | 结构刷新期间屏蔽中间选择事件，按 ID 恢复选择；移除已选节点时保持未选中，不误选替代行 |
| 解绑后旧的异步规范化仍写模型 | 多选绑定从 first 换到 second，排队任务仍把 first 的 parent 写成 parent+child | 规范化回写检查观察者代次和原始值，已解绑任务失效 |
| RTL 文字与 chevron 分离 | 子行文字右边缘为 37.5，目标为 260；文字仍在左侧 | 按布局方向切换物理左右约束；右向文字贴合镜像内容列；切回 LTR 也验证正确 |
| RTL 示例按钮在更新后移出宿主 | 600pt 宿主中按钮 x=908/808，横向栈已缩至196pt，子视图仍按旧600pt宽布局 | 横向栈宽度改变后重新安排原生布局；按钮回到 x=504/404，保持96/88pt宽与12pt间距 |

前三项的初始失败见 [lifecycle-tests.log](before/lifecycle-tests.log)，RTL 行失败见 [rtl-content-tests.log](before/rtl-content-tests.log)。按钮问题的修复前逐状态坐标见 [gallery-layout.json](before/gallery-layout.json)，截图见 [rtl-single.png](before/rtl-single.png)。这些数据保留原样。

TreeView 的结构比较仍遍历全部输入节点；结构变化仍会调用原生 `reloadData()`。这次消除了**结构不变时的重建/重挂载**，没有声称任意树更新变成常数时间。多选规范化仍按现有树选择语义执行。

## Gallery 与参照源码

新增 `TreeViewGallerySample.swift` 并接入目录和质量门禁。示例包括单选/三态多选切换、双向展开集合、展开 Remote 时加载子级、折叠/重置、Return 调用、单条目拖放的应用侧数据更新。文字明确说明一次拖动一个条目。

参照本地 WinUI 2.3.1 源码：

- `microsoft-ui-xaml-winui3-release-2.3.1/src/controls/dev/TreeView/TreeViewItem.xaml`
- 同目录 `TreeView_themeresources.xaml`、`TreeViewItem.cpp`、`ViewModel.cpp`

保留既有 32pt 行高、每级16pt缩进、三态选择与镜像键盘行为。本轮没有修改这些 WinUI 度量，也未声称 macOS 字体与 Segoe 字形一致。

## 验证

- 全量 XCTest：**263 项，0 失败**（交接基线254项，本轮增加9项）。覆盖稳定身份、重排/删除选择、内容更新、解绑回写、延迟子节点、RTL 切换、栈缩放和方向切换。
- Gallery Xcode Debug 构建：**BUILD SUCCEEDED**，`CODE_SIGNING_ALLOWED=NO`。
- Release 质量门禁：**PASS**；目录121项，其中 **60 个直接示例**完成 light/dark/RTL 挂载（原基线59个）；TreeView 仍为 Partial。
- `FluentKitValidation`：**PASS**。
- 独立 Release Gallery 驱动：**15/15 状态通过**，15张截图；逐状态坐标见 [results.json](after/gallery/results.json)。人工检查 light/mixed、dark/lazy-loaded、RTL/single 的文字、复选框、选中行和按钮布局。
- 完整日志与门禁原始数据见 [after](after/)。测试仍记录 Grid 极窄缩放用例的一条 `Conflicting constraints` 告警（`AuditRegressionTests.swift`）；本批未修改 Collection，需继续定位。Xcode 另有无 AppIntents 依赖时跳过元数据提取的提示。**0失败不等于0告警**。

[run.sh](run.sh) 编译 Release 框架和独立 Gallery 驱动；默认产物写入临时目录，历史审计数据不会被重写。共检查 light/dark/RTL × mixed/checked/lazy-loaded/collapsed/single **15 个状态**，断言可见行数、勾选数量、延迟加载、Return 回调和按钮宿主/父容器边界。通过原生 `keyDown`、控件动作和无障碍按钮动作驱动；截图使用 `CALayer.render`，并非历史 `cacheDisplay` 路径。

复跑命令（在仓库根目录）：

```sh
swift test --scratch-path /tmp/fluentkit-repair-tests -Xswiftc -warnings-as-errors
./tools/run-quality-checks.sh /tmp/fluentkit-tree-quality
./audits/2026-10-31/treeview-lifecycle/run.sh /tmp/fluentkit-tree-visual
xcodebuild -project FluentKitGallery/FluentKitGallery.xcodeproj -scheme FluentKitGallery -configuration Debug -derivedDataPath /tmp/fluentkit-gallery-review CODE_SIGNING_ALLOWED=NO build
```

## 仍待完成

TreeView 多条目拖动、行展开动画尚未实现；本轮未执行真实鼠标拖放，示例 `onMove` 的应用端路径不等于物理拖动验收。CommandBar/MenuBar、AutoSuggestBox、SplitButton 的进一步打磨仍待继续。真实触摸屏、Windows 逐像素对照、真实 IME 与 VoiceOver 没有在本轮验收；调用一次无障碍动作也不能当作 VoiceOver 验收。
