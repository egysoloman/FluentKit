# AutoSuggestBox 外部模型更新与回调一致性

2026-11-01，基线 `d98a84c`（AutoSuggestBox 运行时代码与 `8eb25db` 相同）。本批修复两个独立复现的状态顺序问题，保留外部模型重置优先的规则。未修改 Fluent IME 源码或运行中的输入法。用户新报的鼠标连接后滚动条常驻问题已排入 `../FOLLOW-UP.md` 第 19 项，按要求先完成本批。

## 复现与修复

1. **旧查询结果在回调后重新弹出。** 提供器处理 `Ap` 时同步将绑定改为 `Pear`，宿主已清除旧候选并安排新查询；但旧提供器返回 `Apple` 后，宿主又接收它并重新打开列表。新查询完成前，用户会看到与模型不对应的旧候选。现在在调用提供器前记录现有的文本更新代次，返回后确认查询仍有效才接收结果。
2. **提交新文字时携带过期候选。** 普通闭包绑定没有观察通知：预览 Apple 后，应用把模型改为 Pear，Enter 提交才触发同步。原代码在同步前捕获 Apple，最终发出 `(Pear, Apple)`。现在先同步绑定，再解析当前选中项；外部重置清除选择后发出 `(Pear, nil)`。查询按钮原本就提交 nil，保持不变。

没有增加刷新计时器、全局监听或新的状态容器；更改只涉及提供器返回的有效性检查、提交顺序及 API 注释。

## WinUI 对照与保留的绑定规则

对照仓库内固定源码 `microsoft-ui-xaml-winui3-release-2.3.1`，SHA-256 见 `source-sha256.txt`：

- `AutoSuggestBox_Partial.cpp` 451–500：每次文字变化更新计数，区分 UserInput / ProgrammaticChange / SuggestionChosen；只有 UserInput 更新 `m_userTypedText`。
- 2274–2294：先发 TextChanged，再处理应用提供的新结果。`AutoSuggestBoxTextChangedEventArgs_Partial.h` 37–55 的 CheckCurrent 用计数判断事件是否仍对应当前文字。Fluent 的同步提供器由框架调用，因此本批在返回边界检查已有的代次，防止旧结果覆盖新状态；不是新增 WinUI CheckCurrent 的公开 API。
- 885–970、1127–1146：失焦关闭、聚焦时按条件显示，取消恢复用户输入。不能仅从同名文本通知推断 AppKit 的聚焦生命周期与 WinUI 一致。
- [Microsoft 的 TextChanged 文档](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.controls.autosuggestbox.textchanged) 也区分文字变更原因。Fluent 继续保留已公开的字符串回调和带原因回调，不在这一批改变事件 API。

**外部绑定更新与 WinUI 直接设置 Text 并非完全相同的策略。** 用户原始审计要求外部模型重置不能在编辑结束后被旧值写回。Fluent 因此把已应用的外部值作为后续取消的基准，Escape 保留 Pear；WinUI 源码中直接程序化设置 Text 不改写 `m_userTypedText`。本批明确记录并补充 API 注释，没有为了照搬该内部字段而重新引入已修的模型覆盖问题。

## 验证

四项新增测试中，旧基线有两项失败、共 3 处断言失败；另外两项覆盖失焦再进入后的取消及外部重置保护。修复后 AutoSuggestBox 24 项针对性测试及全量 **445 项测试**通过。

独立 Release 原生探针覆盖 LTR/RTL、UpdateTextOnSelect 开/关，以及普通失焦再进入、聚焦时重置、失焦时重置、闭包绑定 Enter、查询按钮、提供器重置后无结果/有新结果，共 **28 个状态**。

| 核查 | 修复前 | 修复后 |
| --- | --- | --- |
| 闭包模型重置后 Enter | 4 个状态提交 Pear 并携带 Apple | 4 个状态提交 Pear、候选 nil |
| 提供器回调替换查询 | 8 个状态曾重新显示旧 Apple 行 | 8 个状态均不显示旧行 |
| 新查询返回 Pear result | 最终显示新结果 | 仍显示新结果，没有用全部关闭掩盖问题 |
| 新查询无结果 | 最终关闭 | 保持关闭 |
| 失焦/再聚焦后取消、外部重置及查询按钮 | 模型和文字正确 | 保持正确 |

比较器记录的字段差异由 **12 → 0**，不是 12 项新增缺陷。原始失败、旧源码及旧对象哈希在 `before/`；同一探针的修复后结果在 `after/`。普通采样使用原生字段编辑器及命令，不是物理键盘延迟测量。

Gallery Debug 构建、FluentKitValidation 和 Release 质量门禁通过。GUI 测试、原生探针、CUA 串行运行。

实际 CUA 隔离窗口采用同一个普通闭包绑定，按键输入 `ap` → Down 显示 `Apple` → Cmd+Shift+R 只把模型改成 `Pear` → Enter。最终 AX 树显示字段为 `Pear`、状态为 `Submitted: Pear; chosen: none`，字段仍聚焦。应用回调原始日志在 `after/ui.jsonl`。最初 `typeText` 后没有得到可导航列表，未将那几次操作计为成功；使用坐标聚焦及原生字母按键的连续步骤明确观察到 Apple 预览后才执行提交验证。此工具路径不等同于物理键盘或真实 IME 验收。隔离窗口已退出。

## 边界与后续

“重新聚焦把预览词当作查询”这条初始假设，在本批原生路径中没有复现，未据此删除或重写聚焦逻辑。当前焦点测试核查取消后的字段/模型以及查询值，没有证明无需输入即可重新打开列表，也没有覆盖所有程序化焦点入口。完整 OnGotFocus 对齐、CheckCurrent 式事件有效性 API、真实系统拼音候选及 VoiceOver 继续保留，不能把本批修复当作 AutoSuggestBox 全契约已验收。

```sh
swift test --scratch-path /tmp/fluentkit-repair-tests --filter AutoSuggestInteractionTests -Xswiftc -warnings-as-errors
zsh tools/run-quality-checks.sh audits/2026-11-01/autosuggest-focus/quality
zsh audits/2026-11-01/autosuggest-focus/run-native.sh "$TMPDIR/fluentkit-quality-release/out/Products/Release" audits/2026-11-01/autosuggest-focus/after
python3 audits/2026-11-01/autosuggest-focus/check-results.py
```

重建旧版可使用独立 checkout `d98a84c`，运行同一最终探针。`build-submit-app.sh` 构建隔离的闭包绑定交互窗口；菜单 Cmd+Shift+R 只改测试模型，保持字段焦点，供 Enter 提交验证。
