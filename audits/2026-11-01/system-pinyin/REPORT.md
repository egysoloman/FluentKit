# 系统拼音候选：客户端坐标核查，尚未关闭真实 IMK 验收

2026-11-01，框架基线 `8eb25db`。本批没有改框架、Gallery 或 Fluent IME 运行时代码，也没有安装、替换或停止正在运行的输入法。

## 当前结论

录屏顶部蓝色候选条已由用户确认为 **macOS 自带拼音**，不是设置页内嵌的 Fluent 候选条。本批没有得到足以归因的系统候选窗口偏移复现。实际设置客户端在三个宽度下返回的文字屏幕矩形随控件同步移动；这只验证客户端坐标，不能据此声称候选浮层已经正常。

当前自动输入没有稳定建立系统拼音组合状态。初版日志中 SCIM 输入源下的 `hua` 是普通文本；一次 `hasMarkedText == true` 发生在 Fluent IME 输入源下。原生 AppKit 对照轮的 9 次显式坐标查询全部为普通文本，系统拼音组合查询为 **0**。因此没有增加固定偏移、额外的坐标失效通知或重写 `firstRect`。

## 录屏与代码归属

- 原视频：`/Users/stars/Movies/屏幕录制/录制于 2026-11-01 00.31.23.mp4`，1512×982、120fps、11.408333 秒。`recording-contact.png` 是每秒两帧的索引；`recording-8.2.png` 保留完整帧。
- 8.2 秒处顶部搜索框内为 `hua`，系统蓝色候选条位于搜索框下方；正文中仍有另一条 Fluent 候选示例。视频没有展示系统候选打开期间移动/缩放窗口的过程。候选宽于搜索框本身不足以证明客户端坐标错误。
- 实际 `SettingsWindowController` 顶部使用 `FluentSearchTextField`，不是 `FluentAutoSuggestBox`。原生 `NSTextView` 提供输入上下文及 `firstRect`，框架没有自定义候选窗口定位。搜索修改会重新构建正文，但沿用搜索框及编辑器。
- Fluent IME 的 `FluentInputController` / `CandidatePanel` 是另一条 IMK 路径。前批独立探针的 6pt 边框重叠和 95pt 缩放后滞后继续保留在 `../candidate-popup/REPORT.md`，不能移植为本视频的结论。

Apple 的 [`firstRect(forCharacterRange:actualRange:)`](https://developer.apple.com/documentation/appkit/nstextinputclient/firstrect(forcharacterrange:actualrange:)) 契约是字符在屏幕中的矩形，零长度范围为光标矩形；不是整个控件外框。[`invalidateCharacterCoordinates()`](https://developer.apple.com/documentation/appkit/nstextinputcontext/invalidatecharactercoordinates()) 用于通知输入系统更新缓存位置。是否需要补充失效通知，仍须先复现真实候选与客户端坐标分离，不能仅凭 API 存在就添加。

## 独立客户端与结果

`SettingsPinyinAudit.swift` 编译实际 IME 设置源码、当前框架及新构建的 Core，使用独立 bundle ID 和临时 Rime 用户目录。没有注册 IMK server，没有修改全局输入源或主题。对照窗口使用未经 Fluent 子类化的 `NSSearchField`、`NSTextField`。

普通事件采样不主动调用 `firstRect`，避免观测本身强制布局。只有菜单“Record client coordinates”（Cmd+Shift+R）明确查询矩形。窗口宽度菜单改变本测试窗口的尺寸；所有实际界面操作通过 CUA 完成。

| 客户端 | 窗口宽度序列 | 输入控件宽度 | 显式查询 |
| --- | --- | --- | --- |
| 实际设置页搜索框 | 640 → 600 → 1000 → 640pt | 310 → 270 → 480 → 310pt | 4 |
| 原生 NSSearchField | 640 → 600 → 1000 → 640pt | 600 → 560 → 960 → 600pt | 4 |
| 原生 NSTextField | 640pt | 600pt | 1 |

- 实际设置搜索框的编辑器身份不变；宽窗口使控件与字符矩形同时向右移动 **95pt**，恢复后回到原坐标。
- 9 次查询的文字均为 `hua`、光标矩形宽度为 0、字符矩形位于控件范围内；同一控件的相对文字坐标保持不变。`checks.json` 为 0 个几何检查错误。
- 初轮 102 条记录在 `client-initial/states.json`；对照轮 84 条记录在 `client-reference/states.json`。这些是事件记录数，不是独立测试数量。输入源在会话中出现 SCIM、Fluent IME、ABC，不能假设持续使用同一种输入法。
- 实际设置页与原生搜索框在同一 Fluent IME 输入源下均出现直接输入普通 `hua`；这不构成系统拼音正常或框架损坏的证据。原生普通文本框查询时为 ABC，同样不算中文输入验收。
- 初版探针缺少 Edit 菜单，Cmd+A 未选择全部文字；已补齐对照轮菜单。实际 IME 的 `main.swift` 本来就有编辑菜单，不能把探针遗漏报成应用缺陷。

## 构建与并行修改边界

旧的 Core 产物缺少应用后来新增的 ClipboardHistory/GIFLibrary 类型，初次链接失败保留在 `client-build-stale-core.log`。重新构建 Core Release 后通过。探针闭包的 actor 警告修正后，最终客户端以 `-warnings-as-errors` 编译通过，见 `client-reference-build.log`；没有通过关闭诊断规避编译问题。

构建时源码和对象文件哈希分别保存在两个客户端目录。首次检查发现外部应用的 `Preferences.swift`、`InputSession.swift`、`RimeEngine.swift` 已与构建记录不同，发现时哈希/时间及测试二进制哈希在 `end-provenance.json`；报告整理期间 `CandidateView.swift`、`FluentInputController.swift`、`SettingsWindow.swift` 也发生变化，核查清单见 `checks.json`。本批没有修改这些文件，也没有覆盖并行工作；结果适用于记录的构建，不能冒充后续应用改动的验收。后续重新运行检查可能发现更多来源变化，这不是本批几何回归。

由于没有修改运行时代码，没有重复跑 441 项框架测试；最近框架门禁仍以 `../autosuggest-cancel/REPORT.md` 为准。测试客户端已退出，正在运行的输入法未被停止。

## 复现与下一步

```sh
swift build --package-path '/Users/stars/Downloads/Fluent IME' --target FluentIMECore -c release --scratch-path /tmp/fluentkit-ime-system-pinyin -Xswiftc -warnings-as-errors
zsh audits/2026-11-01/system-pinyin/build-client.sh "$TMPDIR/fluent-system-pinyin-client.app" /tmp/pinyin-client-review
python3 audits/2026-11-01/system-pinyin/check_results.py
```

编译脚本需要当前 FluentKit Release 产物及 IME 资源；可用脚本中的环境变量覆盖来源。启动测试 app 后，Cmd+Shift+B 打开原生对照，Cmd+Shift+S 返回设置页，Cmd+Option+1/2/3 切换 600/640/1000pt，Cmd+Shift+R 查询坐标。最后的 Python 命令只核查本次已保存数据，不重新执行 UI 操作。

下一次真实输入验收需明确固定系统拼音中文状态，在实际与原生对照客户端均产生 marked text，记录系统候选窗口，再检查移动/缩放、候选翻页、提交和取消。当前数据不包含这些结果。继续保留第 5/18 项，不因本批普通文本几何正常而关闭。
