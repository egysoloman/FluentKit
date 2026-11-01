# 实际窗口交互记录

全部为 CUA 原生操作。GUI 测试/探针运行时没有并行操作这些窗口；隔离应用已退出，没有操作运行中的 Fluent IME。

## 实际 Gallery

独立副本与哈希见 `gallery-provenance.json`。此次窗口包含 scope 和文本代理修复，尚未追加消费 Tab 时的设备记录保护；普通 CheckBox 页面不使用显式 scope。

1. Basic input → CheckBox，经 Tab 到 Interactive sample 的折叠头。
2. Tab 到 Remember selection，Space 从选中改为未选；可见焦点边框。
3. Shift-Tab 回示例头，再 Shift-Tab 到 Settings。
4. 较早的窗口策略版本还检查：Space 折叠后 Tab 跳过隐藏 CheckBox，重新展开后能够到达并激活；搜索 RadioButton 后，Tab 到示例单选项并用 Space 改变选择，可见焦点边框。

AX 树没有在自绘选择控件上稳定给出 focused 标识，因此使用实际 Space 改值及可见边框交叉验证；不将此视为 VoiceOver 完整焦点播报验收。另一次 Command-F 未聚焦搜索，后来通过 AX 点击完成搜索；该现象未独立定位。

## CycleApp

`cycle-ui-before-device-guard.jsonl`：动态 A/C/B 顺序的循环、反向循环、重排、对话框首尾循环、Escape 回原焦点；搜索 Ap → Down Apple → Tab Ap 在该次成功。

`cycle-ui-unstable-identities.jsonl`：最终运行时代码，从程序化种入的 touch 经 Tab 变成 keyboard；B→A→C、反向以及对话框首尾循环通过。建议使用默认随机 ID，该次 Tab 后界面仍为 Apple。

`cycle-ui-stable-first.jsonl`：只把建议换为稳定 ID。首次输入后 Down 没有预览；重新全选输入后 Down 显示 Apple，Tab 到 Clear 时 AX diff 没有报告文字恢复。这次未记录内部查询/选中项，不能区分候选提前关闭、刷新时序或 AX 结果缓存，保留为未结观察。

`cycle-ui.jsonl`：最终 fixture 增加只读状态记录。Down 前 selectedIndex=-1、userTypedText=Ap；Down 后 selectedIndex=0、query=Apple。Tab 后 AX 显示 Ap、焦点为 Clear；退出前内部状态也为 query=Ap、selectedIndex=-1、suppressPresentation=true。事件 monitor 顺序导致已消费的 Tab 不在 fixture 的 keyDown 记录里，焦点记录和后续状态仍在。该成功样本不能覆盖前一次不一致。

`cycle-ui-provenance*.json` 分别记录二进制、对应 fixture 和 FluentFocus 源码 SHA-256。稳定身份与随机身份的独立确定性对照另见 `candidate-refresh.json`，该对照没有 scope，也不使用本批事件分派助手。

仍需修正/验证：Clear/Query 辅助按钮 TabStop 与 WinUI 模板不符；动态候选替换的文字契约；真实输入法与 AX 刷新。没有以此次 CUA 成功替代物理设备或输入法跨进程验收。
