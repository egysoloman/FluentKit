# CommandBar 更新与溢出生命周期独立复核

日期：2026-10-31。接续 `3025ca8`；开始时工作区干净。原始审计目录及其他智能体已经提交的工作保持原样。本批聚焦 CommandBar；MenuBar 的更新生命周期问题已确认，留待下一批处理。

## 结论与证据

原先通过的测试没有证明菜单在声明式刷新、尺寸变化时仍能正常工作。本次先增加复现，再对照 WinUI 源码修改，并检查原生渲染截图。

Release 探针覆盖浅色／深色 × LTR／RTL，每组记录打开、5 次相同内容刷新、变宽、变窄，共 16 个状态。四种外观方向的结果一致：

| 检查 | 修复前 | 修复后 |
| --- | --- | --- |
| 5 次刷新后保留的主／次命令对象 | 0/4、0/1 | 4/4、1/1 |
| 刷新后原溢出窗口、焦点 | 菜单关闭，均丢失 | 原窗口与焦点保留 |
| 刷新触发 IsOpenChanged | `[false]` | 无事件 |
| 200pt 工具栏打开后隐藏的溢出主命令 | 2 个（Share、Delete 空白） | 0 个 |
| 扩至 360pt 后仍在溢出的主命令索引 | `[3]` | `[]` |
| 再缩至 160pt | `[1,2,3]`，但全部隐藏 | `[1,2,3]`，均可见 |

原始数据：[`before/results.json`](before/results.json)、[`after/results.json`](after/results.json)。基线复用了上一批质量门禁生成的 Release 库；两次库对象的 SHA-256 分别保存在对应目录的 `library-sha256.txt`。基线 28 张图、最终 32 张图（旧实现刷新后关闭了 4 个弹窗，因此少 4 张）。这些是 macOS 上 CALayer 直接渲染的 2× 截图，不是 Windows 像素对拍。

打开时溢出菜单的直接证据：

| 修复前 | 修复后 |
| --- | --- |
| ![原实现缺失两行](before/images/light-ltr-open-popup.png) | ![修复后显示 Share 和 Delete](after/images/light-ltr-open-popup.png) |

## 修改依据与边界

对照本地 `microsoft-ui-xaml-winui3-release-2.3.1/src/dxaml/xcp/dxaml/lib/CommandBar_Partial.cpp`：

- `OnPrimaryCommandsChanged` / `OnSecondaryCommandsChanged`（1839–1934 附近）在现有命令集合上更新视觉状态和测量，并使用当前 IsOpen；不是每次更新都先关闭菜单。
- `StoreFocusedCommandBarElement` / `RestoreCommandBarElementFocus`（4007–4076 附近）保存命令元素，在集合和尺寸变化后恢复它的焦点，包括主区域与溢出区域之间的迁移。
- AppBar 模板的主区域宽度与溢出行宽度不同。FluentKit 现在独立测量主区域模板，不再用当前溢出行的宽度判断是否能够移回工具栏。

实现内容：

1. `FluentCommandBarView` 一次更新两个命令数组；`FluentCommandBar` 按身份复用按钮、切换按钮和分隔线，原地更新标题、图标、动作、启用状态、快捷键文字与勾选状态。
2. 新增可选 `FluentCommandBarItem.id` 和 `setCommands(primary:secondary:)`。动态插入／重排使用全局唯一的稳定 ID；跨组移动应通过该原子更新方法或一次声明式刷新完成。没有 ID 时按组与位置保留身份。控件种类改变时会替换该控件。
3. 打开的溢出窗口与 presenter 复用，重新计算大小、位置、行内容和可访问性子项；稳定的组间分隔线也保留。刷新不会冒充打开／关闭操作，也不会更改本次打开所采用的输入设备密度。
4. 主命令进入溢出后解除隐藏；离开溢出后恢复主模板。焦点跨两个 AppKit 窗口移动时跟随命令；删除或禁用焦点项时选择有效后继目标。后台更新不主动激活窗口。
5. 模型勾选值更新不调用用户动作；连续点击原生切换按钮时回调实际新值。关闭动画使用代次检查，旧动画不能拿走重新打开的菜单中的控件或焦点；已移除的工具栏也不会留下延迟关闭的子窗口。
6. 未获得有效宽度的新控件不提前制造“全部溢出”状态，保留原有首次布局事件语义。

## 截图复核额外发现

中间版本曾通过 276 个测试和 16 组状态检查，但人工检查截图发现：从短菜单扩为长菜单后，旧动画 mask 仍维持原高度，把新增的第一行 Paste 裁掉了。保存的证据是 [`intermediate-before-clip-fix.png`](intermediate-before-clip-fix.png)，对应库哈希见 [`intermediate-library-sha256.txt`](intermediate-library-sha256.txt)。**它是本次修复过程中的中间版本，不能当作修复前基线或最终结果。**

随后将 popup 的完整呈现状态重置提取为共享 `settlePresentation()`；CommandBar 在原地调整窗口尺寸并完成布局后更新裁剪区域，必要时结束旧入口动画。新增回归断言检查 mask 与动画根区域一致，Release 探针也增加 `clipCoversPopup`，在提交 AppKit 的 backing layer 树后读取裁剪区域。最终窄菜单完整显示 Paste、Share、Delete、Settings。

这次发现说明：对象身份、可见性字段和测试数量都不能代替实际渲染检查。

## 验证

- 全量 XCTest：276 项，0 失败（新增 10 项生命周期测试），warnings-as-errors；原有动态溢出事件测试保持不变。
- 测试日志的 AppKit 约束冲突检查通过。
- 原生 `FluentKitValidation` 通过。
- Release 质量门禁通过，包含更新次数、挂载身份、外部重置、字体、材质与 60 个直接 Gallery 样例检查。
- Xcode Gallery Debug 构建通过，关闭签名。
- 独立 Release 探针 16 个状态通过，并检查裁剪区域；最终截图人工检查。四种外观方向各自的工具栏／菜单在 5 次刷新前后 PNG 字节完全一致（8 对）。

原始日志与 JSON 位于 `after/`。测试包括菜单保持展开、动作和模型值更新、稳定 ID 重排／跨组移动、禁用／删除／种类替换后的焦点、立即关闭重开、移除工具栏后的延迟关闭、主命令焦点跨区域移动、打开设备密度、两种方向的反复缩放及动画裁剪几何。非活跃测试进程验证各窗口的 first responder；活跃窗口另检查 key-window 状态。触摸密度由输入设备记录驱动，不能据此声称真实触摸屏已验收。

环境：macOS 27.2（26B123），Apple Swift 6.4，Swift 5 language mode。复跑：

```sh
swift test --scratch-path /tmp/fluentkit-repair-tests -Xswiftc -warnings-as-errors
./audits/2026-10-31/commandbar-lifecycle/run.sh /tmp/commandbar-lifecycle-review
./tools/run-quality-checks.sh /tmp/fluentkit-quality-review
```

## 尚未完成

- MenuBar 仍会在 `synchronizeItems` 中无条件关闭菜单；其 flyout 内容目前不可原地更新，下一批需要连同共享菜单生命周期处理。
- 本批不宣称 CommandBar/MenuBar 已达到完整 WinUI 对齐；长菜单滚动、完整键盘流程及其他变体还需专项复核。
- Windows 逐像素对照、真实触摸、真实 IME 与 VoiceOver 仍未验收；AutoSuggestBox、SplitButton 等后续打磨继续保留。
