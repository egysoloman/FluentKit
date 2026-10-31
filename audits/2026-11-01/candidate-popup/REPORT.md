# 搜索建议浮层与输入法候选窗复核

2026-11-01。框架修复基线：`00c08f2`。本批修复 AutoSuggestBox 外层滚动/布局导致的脱锚；实际 IME 的独立候选窗仍有待跨进程确认的应用侧问题，不能据此宣布用户的候选窗问题全部解决。

## 已确认并修复的框架缺陷

AutoSuggestBox 的独立 NSPanel 原先只跟踪窗口移动/缩放及输入控件自身的布局。外层 NSClipView 滚动或祖先容器平移，不会重新布局该控件，因此建议框留在旧屏幕坐标。输入框完全滚出可见区域时，建议框也残留。

`AutoSuggestInteractionTests.testPopupTracksScrollingAncestor` 的初始回归在修改前失败 5 处。Release 探针以深浅色、LTR/RTL 各执行连续滚动、祖先平移、窗口缩放、完全裁切、返回、重新输入和 Escape，共 108 个状态。相同探针的代表值如下：

| 场景 | 修改前 | 修改后 |
| --- | --- | --- |
| 外层滚动 35pt | 下方间距从 2pt 变成 −33pt | 保持 2pt |
| 外层平移 15pt、7pt | 横向误差 −15pt，垂直间距 9pt | 横向误差 0，间距 2pt |
| 输入框完全裁切 | 建议框仍开着 | 关闭 |
| 滚回输入框 | 旧建议框仍开着 | 等待下一次输入再打开 |

现在浮层按对象观察输入框及其祖先的 frame/bounds 通知，移动时重新定位；完全裁切时关闭。关闭时移除观察，恢复输入后重新建立观察；不改变调用者的通知标志，不增加轮询。修改后全部 108 个动态状态通过，焦点保持在字段编辑器。

WinUI 的 [AutoSuggestBox 位置实现](https://raw.githubusercontent.com/microsoft/microsoft-ui-xaml/main/dxaml/xcp/dxaml/lib/AutoSuggestBox_Partial.cpp) 从文本框变换计算建议位置；FluentKit 的独立 AppKit 窗口需显式处理祖先几何变化。本报告没有据此推断 WinUI 对所有裁切场景的关闭策略。

## 三种容易混淆的浮层/候选内容

1. **框架 AutoSuggestBox**：本批已修。实际 IME 设置顶部使用 FluentSearchTextField，并非 AutoSuggestBox，不能把这项修复直接算作设置页候选窗修复。
2. **设置页“试输入”内嵌 CandidateView**：没有组合时继续显示示例候选是当前示例逻辑；它不是滞留的输入法浮窗。
3. **输入法独立 CandidatePanel**：用户录屏顶部搜索框出现蓝色胶囊候选条，其样式与当前应用源码的灰色选中项/竖向强调条不同。录屏当时的输入法和已安装构建尚未确认。

电脑界面检查使用链接当前框架的独立设置测试 App。UI 按键 `h/u/a` 后出现组合文字，Escape 清空组合且保持当前页面；检查前后当前输入源均为 `org.fluentime.inputmethod.FluentIME.Hans`。工具捕获的是客户端主窗口，未取得独立输入法候选窗截图，因此不据此宣称候选位置、选词或全部真实 IME 流程验收通过。测试 App 已退出；未安装、替换或停止用户输入法。

`run-ime.sh` 还编译了当前 IME 应用源码，隔离调用实际 CandidatePanel，并使用实际设置搜索框原生编辑器的 `firstRect` 驱动它。展开/折叠各 6 个状态保存在 `ime/`，应用源码哈希随附，未修改应用源码。

- 使用当前 1pt 文字行间距时，面板顶边比搜索控件底边高 6pt，存在重叠。
- 窗口变宽后，仅布局客户端，候选面板横向落后 95pt；再次调用 `present` 后归零。
- 候选面板不抢键盘焦点；关闭/空组合同时隐藏阴影，再开时只有一个可见阴影。

这是**隔离几何复现**，没有通过 IMK 的跨进程 `attributes(forCharacterIndex:lineHeightRectangle:)` 传输。需继续验证真实客户端返回的矩形与几何变化回调，再决定客户端锚点或应用候选面板的修复。不能用增加一个固定间距掩盖不同字体/控件高度的问题，也不能将隔离探针结论冒充录屏归因。此分支保留在总计划中。

## 验证与复现

380 项测试、原生验证、Gallery Debug 构建与 Release 质量门禁通过；无约束诊断。框架新增测试在原有 16 项 AutoSuggestBox 测试之外覆盖祖先滚动与平移，并检查裁切关闭、返回不复活以及再次输入正确打开。原始失败日志和 Release 数据均保留。

```sh
swift build --target FluentKit -c release --scratch-path "${TMPDIR}/fluentkit-quality-release"
zsh audits/2026-11-01/candidate-popup/run.sh /tmp/candidate-popup-review
python3 audits/2026-11-01/candidate-popup/check_results.py /tmp/candidate-popup-review/results.json
swift test --scratch-path /tmp/fluentkit-repair-tests --filter AutoSuggestInteractionTests
zsh audits/2026-11-01/candidate-popup/run-ime.sh /tmp/ime-candidate-review
```

IME 探针依赖与 `../search-geometry/REPORT.md` 相同。`FLUENTKIT_POPUP_LIBRARY` 可指定旧框架对象；本批旧 Release 对象 SHA-256 为 `e450c8ee63f1f94bf48b59641a4282584cd365bf1dc278e77c5210221af087d6`。原生字段文字可能不完整出现在 layer 采样里，几何检查以实际窗口坐标、焦点和可见性数据为依据。
