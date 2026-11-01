# AutoSuggestBox 取消预览与辅助按钮键盘顺序

2026-11-01，基线 `9062bee`。本批接续上一批的搜索建议问题，修复两个有源码和实际窗口复现的缺陷。没有修改或替换 Fluent IME；设置页顶部的系统拼音候选条另属客户端输入法路径。

## 上游契约与实现

对照本地 `microsoft-ui-xaml-winui3-release-2.3.1`，文件哈希见 `source-sha256.txt`：

- `src/dxaml/xcp/dxaml/lib/AutoSuggestBox_Partial.cpp` 1127–1146：Tab 仅在建议列表打开时执行取消，Escape 总是恢复 `m_userTypedText`；不以 SelectedItem/SelectedIndex 是否存在作条件。Tab 随后继续正常导航。
- 同文件 2349–2400：取消选中项不会重新把旧预览当作用户输入；只有非空 SelectedItem 才写预览并发出 SuggestionChosen。
- `src/controls/dev/AutoSuggestBox/AutoSuggestBox_themeresources.xaml` 241–242：DeleteButton/QueryButton 的 `IsTabStop=False`。

FluentKit 原先在 `selectedIndex >= 0` 时才恢复查询。提供器重新生成身份或移除选中项后，index 变为 -1，但文本仍是 Apple；因此 Tab/Escape 无法回到用户输入的 Ap。现取消无条件走恢复路径，已有的 Tab 开启条件保留，文本与绑定仍同步更新，并发出已有的 ProgrammaticChange 事件。

辅助按钮设置 `refusesFirstResponder`，使普通原生遍历及显式 scope 都跳过它们。保留 AppKit 的按钮动作和可访问性暴露。macOS 的 AX 映射没有照搬 XAML 的 Raw 标志；本批真实 AX 操作仍能清空与查询。

## 修复前后证据

`CancelAudit.swift` 通过原生字段编辑器执行命令，没有使用 FluentFocus 的内部助手。覆盖 LTR/RTL、稳定候选/身份替换/选中项移除/清空列表/外部重置，以及 Tab/Shift-Tab/Escape/Enter，共 40 个状态。

| 路径 | 修改前 | 修改后 |
| --- | --- | --- |
| 预览后替换身份或移除选中项，再 Tab/Escape | 留下 Apple | 恢复 Ap，关闭建议 |
| 候选清空使列表先关闭，再 Tab | 保留 Apple | 保持此行为 |
| 同上，再 Escape | 留下 Apple | 恢复 Ap |
| 外部重置为 Pear 后取消/提交 | 保留新模型 | 保留新模型 |
| 移除选中项后 Enter | 提交当前文字、无过期候选 | 保持此行为 |
| 辅助按钮的 Tab 资格 | Clear、Query 均可停靠 | 两者均跳过 |
| 普通原生 Tab | 先到辅助按钮 | 到后续控件 |

相同原生探针及比较器的 118 项字段差异归零，见 `comparison.json`；这是状态检查次数，不是性能或物理输入延迟。三项新增测试覆盖取消事件原因、关闭列表边界、辅助按钮与编辑焦点，另扩充外部重置保护。最终 441 项测试、FluentKitValidation、Gallery Debug 构建、Release 构建及质量门禁通过。

实际 CUA 窗口使用相同的 `TraceApp.swift`，父级直接显示绑定查询，以确保预览会引起真实声明式刷新：

1. 修改前，IDs: recreated 下 Ap → Down Apple → Tab，字段和模型仍为 Apple，焦点到 Clear。
2. 修改后，同一路径恢复 Ap，焦点到 After search；Shift-Tab 回到字段。
3. 通过 AX 按钮操作 Clear 清空文字并保留编辑焦点；Query 关闭建议并保留字段焦点。再次 Down 不进入已关闭列表，Escape 恢复 Ap。
4. 切到 IDs: stable，重复 Ap → Apple → Tab，同样恢复 Ap 并到后续按钮。

原始内部状态与焦点日志在 `before/ui.jsonl`、`after/ui.jsonl`，对应源码/二进制 SHA-256 在 `provenance.json`。日志额外记录窗口激活及可见矩形；有些 Tab 先被框架消费，不进入 fixture 的 keyDown monitor，仍有第一响应者与后续模型记录。按钮的提交回调另由单元测试验证。

## 验证修正与仍开放事项

保留了几次测试夹具修正，不能把它们算作框架缺陷：初稿直接询问 NSButton 自身的 AX getter，得到 ignored/Unknown，但真实跨进程 AX 树有按钮；错误断言已撤回，改用真实 AX 操作。初稿还把单控件的 intrinsic-height 挂载方式用于没有固有高度的复合宿主，后改为明确的可见区域。最后确认直接 `NSWindow.selectNextKeyView(nil)` 不能替代字段编辑器的 `insertTab` 命令：前者在该测试环境保留编辑器，后者及独立原生探针正常导航。最终测试使用实际文本命令路径。初始失败和诊断日志均保留，未为迎合这些断言改动运行时代码。

上一批稳定 ID 窗口曾有一次 AX 仍显示预览词，缺少内部状态。本批旧版稳定 ID 路径及修后稳定 ID 路径均成功，没有重现那次不一致；它仍保留为待查记录，不能把本批确定的身份替换问题冒充唯一归因。

本批保留 FluentKit 既有的外部模型重置优先规则。WinUI 对程序化 Text 更改、失焦再聚焦后 `m_userTypedText` 的完整契约，还需单独对照；不据此宣称全部 AutoSuggestBox 文本行为对等。真实 macOS 拼音候选锚点、跨进程输入及 VoiceOver 完整操作仍未验收。

## 复现

```sh
swift build --target FluentKit -c release --scratch-path "$TMPDIR/fluentkit-quality-release" -Xswiftc -warnings-as-errors
zsh audits/2026-11-01/autosuggest-cancel/run-native.sh "$TMPDIR/fluentkit-quality-release/out/Products/Release" audits/2026-11-01/autosuggest-cancel/after
python3 audits/2026-11-01/autosuggest-cancel/check-results.py
swift test --scratch-path /tmp/fluentkit-repair-tests --filter AutoSuggestInteractionTests -Xswiftc -warnings-as-errors
```

基线产品路径及对象哈希见 `baseline.json`；也可在独立 checkout 构建 `9062bee`。`build-trace-app.sh` 接受产品目录、隔离 `.app` 路径、日志路径三个参数，用于 CUA 复验。GUI 测试/探针/CUA 串行；未使用合成 scrollWheel。两个隔离交互 App 已退出。
