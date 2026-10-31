# SplitButton / ToggleSplitButton 交互与状态复核

日期：2026-10-31。基线：`2fbcd7d`。本批开始时工作区干净，旧审计目录未修改。

## 独立复现

在 `2fbcd7d` 的隔离源码副本运行 6 个回归测试，确认 **21 处断言失败**，见
[基线日志](before/regression-tests.log)和[对应夹具](before/baseline-test-fixture.swift)。
最初的测试夹具遗漏菜单的首次键盘选择，并使用了不稳定的窗口级合成事件分发；修正后才重新建立上述基线。
[最初输出](before/initial-fixture-tests.log)保留用于追溯，不作为缺陷数量依据。

同一份公开 API Release 探针覆盖 **浅/深色 × LTR/RTL × 普通/选中 Toggle × 9 阶段 = 72 个状态**。
[修复前结果](before/results.json)及 [SHA-256](before/library-sha256.txt)保留；截图直接渲染 layer tree，2×，关闭材质效果。

| 独立确认的行为 | 修复前 | 修复后要求 |
| --- | --- | --- |
| 控件位于父视图非零坐标 | 8 个变体均命中失败 | 正确命中；隐藏时不命中 |
| 菜单已打开后再次 `showFlyout()` | 关闭菜单 | 保持同一个 panel |
| 替换同 ID 的菜单标签与动作 | 仍显示 `Save old`、执行旧动作 | 保留行身份，显示新标签并执行新动作 |
| 挪动按钮 30×20pt | 弹窗原地不动 | 同步移动 30×20pt |
| 隐藏/移除按钮、关闭窗口 | 可能留下菜单或捕获的按压 | 清理弹窗与按压 |
| 替换 Toggle 绑定 | 旧异步回调可覆盖新状态 | 只接收当前订阅、当前模型值 |
| 验证型 setter 拒绝勾选 | 按钮显示被拒绝的值 | 恢复模型实际接受的值 |
| 触摸主区域 | 只绘制主区域按压 | 两个区域同时按压；鼠标仍独立 |

另外确认：禁用的原生 Toggle 仍能通过 `invokePrimaryAction()` 改值；无独立 accessibility ShowMenu/expanded 状态；鼠标按压会把另一半边框也压平；主背景没有覆盖分隔列；次区域按压时 hover 分支优先导致箭头颜色错误。

## WinUI 源码依据

本地 `microsoft-ui-xaml-winui3-release-2.3.1/src/controls/dev/SplitButton/`：

- `SplitButton.cpp`：118–218 的鼠标/触摸/键盘视觉状态分支；221 的 OpenFlyout；307 的指针设备记录；324–368 的 Space/Enter、Alt+Down、F4 时序。
- `SplitButton.xaml`：普通与 checked 的分区状态、主背景跨分隔列、primary 最小 35pt / separator 1pt / secondary 35pt。
- `ToggleSplitButton.cpp`：35–57 的 CheckedChanged 与 Click 顺序。
- `SplitButtonAutomationPeer.cpp`：独立 Invoke 与 Expand/Collapse 模式。

本次没有改动 35/1/35 的来源尺寸，也没有把两半合成一个点击动作。

## 修改与验收边界

- 原生 SplitButton 修正坐标命中，实时更新菜单、主题、placement，幂等打开，清理隐藏/卸载/窗口失焦中的按压。MenuFlyout 共用层跟随父窗口移动/缩放，并在关闭父窗口或应用失活时关闭。
- 鼠标各半边独立边框；触摸/键盘/打开菜单时两半按压；补齐菜单辅助功能动作及 expanded 状态。
- Toggle 稳定订阅复用、代次检查、模型值检查和 setter 回读。CheckedChanged 先于 Click；回调中禁用按钮不会取消已接受的这次 Click，但会拒绝之后的禁用调用。最终复核发现并修正了本批禁用守卫导致的重入顺序回归，失败证据保存在 `after/reentrant-regression-before-fix.log`。
- 新增两个直接 Gallery 示例，含禁用、共享 checked 状态、子菜单和延迟更新。
- Gallery 编译独立暴露 `FluentViewBuilder` 的单分支 `if` 无法推断泛型。隔离基线的两个编译测试同样失败，见 [基线编译结果](before/builder-tests.log)。添加具体类型的 `buildOptional` 重载，保留原泛型 API；覆盖单分支、可选绑定、嵌套条件和兄弟视图。

仍标为 **Partial**。真实触摸屏、真实 VoiceOver 操作、Windows 像素对照及全部控件尺寸/对比度组合未验收。
这些合成事件、辅助功能属性断言和本地截图不能替代上述验收。

## 最终验证

- [完整测试](after/tests.log)：**317 项，0 失败**；本批新增 11 项 SplitButton 交互测试和 2 项 builder 条件测试。
- [原生验证](after/native-validation.log)：PASS；测试与原生输出均无 AppKit 约束冲突。
- [Xcode Gallery 构建](after/gallery-build.log)：BUILD SUCCEEDED。
- [Release 质量门禁](after/quality.log)：刷新次数、挂载身份、外部重置、字号、材质及 Gallery 检查通过。
- [Release 探针](after/results.json)：72 状态全部通过，见 [检查输出](after/probe.log)。104 张修复后 PNG 保存在 `after/images/`。
- 人工检查了 8 个变体的 9 个按钮阶段，以及打开、更新、移动时的弹窗。最终重入修复后的 104 张图片与已检查版本 SHA-256 全部一致。
- 直接 Gallery 示例 **61 → 63**；两个 SplitButton 条目仍为 Partial。

探针在模拟触摸之后打开菜单；修复后共享输入追踪器正确记录 touch，因此弹窗采用更高的触摸行。
这解释了前后菜单行高的变化。截图验证了分隔列不再漏出底色、鼠标独立边框、触摸双区域按压、RTL 镜像与更新后文本完整显示；没有宣称 Windows 像素一致。

## 复现

```sh
swift test --scratch-path /tmp/fluentkit-repair-tests -Xswiftc -warnings-as-errors
./tools/run-quality-checks.sh /tmp/fluentkit-quality-results
./audits/2026-10-31/splitbutton-interaction/run.sh /tmp/fluentkit-splitbutton-interaction
```

测试基线应在 `git archive 2fbcd7d` 的隔离副本中加入 `before/baseline-test-fixture.swift` 后运行。
Release 基线使用已构建的旧库并设置 `AUDIT_USE_EXISTING_BUILD=1`，该模式只记录数据，不执行修复后的断言。
