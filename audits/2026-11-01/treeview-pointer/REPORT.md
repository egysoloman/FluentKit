# TreeView 复选框释放与附件命中

基线：`7e6d734`。本批修改框架的 TreeView 事件路由；未修改 Gallery 数据逻辑或已安装输入法。

## 对照与根因

固定参照 `winui3/release/2.3.1`，本地文件哈希见 `before/source-sha256.txt`：

- [TreeViewItem.xaml](https://github.com/microsoft/microsoft-ui-xaml/blob/winui3/release/2.3.1/src/controls/dev/TreeView/TreeViewItem.xaml)：箭头普通模式左右各 14pt padding，多选仅保留尾部 14pt；复选框列宽 32pt、最小高 28pt，位于 presenter 的 2pt 上下边距内。
- [TreeViewItem.cpp](https://github.com/microsoft/microsoft-ui-xaml/blob/winui3/release/2.3.1/src/controls/dev/TreeView/TreeViewItem.cpp)：`OnExpandCollapseChevronPointerPressed` 在按下时展开/折叠。
- [ButtonBase_Partial.cpp](https://github.com/microsoft/microsoft-ui-xaml/blob/winui3/release/2.3.1/src/dxaml/xcp/dxaml/lib/ButtonBase_Partial.cpp)：默认 Release 模式，移动更新按压状态，释放时决定是否调用；失去捕获时清除按压。

原 TreeView 将复选框和箭头都放在 mouseDown 执行。因而按住复选框移出、取消、改变选择模式后，选择已经被写入，不能撤销未完成的点击。原命中框也只是 glyph 左右扩展 7pt，漏掉普通模式两侧及多选模式尾部的有效区域，复选框上下反而占用了 presenter 边距。复选框外观始终传入 normal，悬停和按压没有颜色反馈。

修复后，原生 outline 跟踪复选框的一次按压；在有效区域释放才提交，移出/移回只改变反馈。箭头保留按下触发。取消、失焦、脱离窗口、节点移除/复用及选择模式变化不会在随后释放时修改其他节点。释放前清除捕获状态，避免回调重入。普通行内容继续交给 NSOutlineView，以保留原生行选择和拖动。

绘制命中框使用完整模板尺寸并按 RTL 镜像；保留绘制 glyph 的大小。复选框复用现有 FluentCheckBox 样式的 hover/pressed 状态。本批不宣称这些共享颜色资源已完成 Windows 像素对拍。

## 证据

| 验证 | 修复前 | 修复后 |
| --- | --- | --- |
| 4 项附件回归（含原测试加强） | 33 处断言失败 | 全过 |
| 深浅色 × LTR/RTL × 32/48pt 行高 | 56 个状态，32 处选择值不符 | 72 个状态，选择/展开值均符合预期 |
| 悬停/按压/移出 | 一律使用 normal 外观；按下已经修改值 | hover/pressed 有区别；移出恢复 normal，释放不修改值 |
| 实际 Gallery CUA 操作 | 先前点击路径见上一批报告 | 点击 Notes 后 Checked 1→2；从复选框拖出释放仍为 2；点击 Specs 箭头后方留白正确展开 |

原生结果、颜色分量与 layer 渲染图在 `before/native/`、`after/native/`。CUA 的三份状态、截图和真实事件记录在 `after/interactive/`；该取消拖动没有创建原生数据拖放会话，符合附件行为。数据拖放落地仍沿用上一批未验收结论。

原生探针直接调用测试窗口的事件处理，不是物理鼠标或触屏。旧代码漏掉 padding 后会进入 AppKit 普通行的同步跟踪，直接调用没有后续系统事件，因此旧探针用 `--skip-chevron` 跳过这两帧；旧命中缺陷由不进入跟踪循环的 XCTest 保存。未将测试驱动的等待解释为框架死锁。

全量 **404 项测试，0 失败**；AppKit 约束诊断、原生验证、Release 质量门禁、Gallery Xcode 构建通过。相关日志均在 `after/`，`check_results.py` 检查原始值及构建结果。

## 发现但未关闭

CUA 读取辅助功能树后，未展开的 Remote 也出现了 `Expanded remote` 状态。源码将 `onExpanding` 放在 `shouldExpandItem` 中；这里混合了资格查询与实际展开副作用，下一批需独立验证 AX 查询是否提前触发加载。当前 `after/interactive/states.json` 第三次记录为 `Expanded specs`，随后的 AX 读取显示 `Expanded remote`，而 Remote 仍折叠。不能将此当作 VoiceOver 验收通过。

跨树传输、完整原生数据拖放、展开动画、Windows 逐像素对拍、真实触屏与 VoiceOver，以及真实 IMK 候选定位继续开放。

## 重跑

```sh
swift test --scratch-path /tmp/fluentkit-repair-tests -Xswiftc -warnings-as-errors
swift build -c release --scratch-path "$TMPDIR/fluentkit-quality-release" -Xswiftc -warnings-as-errors
zsh audits/2026-11-01/treeview-pointer/run-pointer.sh /tmp/tree-pointer-results
zsh tools/run-quality-checks.sh /tmp/tree-pointer-quality
zsh audits/2026-11-01/treeview-pointer/build-review.sh
python3 audits/2026-11-01/treeview-pointer/check_results.py
```

`run-pointer.sh` 使用已有 Release 产品，以便同一探针能运行于两个版本；不自动更新基线。`build-review.sh` 仅创建独立验证应用，沿用上一批的只读事件记录器；不会覆盖旧审计数据。
