# 用户问题与后续验收计划

更新：2026-11-01。按用户要求顺序推进，保留原审计全部范围。修复一条根因、测试通过或控件类型存在，均不代表整项视觉验收结束。

## 当前处理顺序

| 顺序 | 状态与任务 | 关闭该项需要的证据 |
| --- | --- | --- |
| 1 | **本批背景路径已修并完成联合复验。** IME 材质层与 Gallery 染色层/遮罩分别修复，导航/Undo scope 的旧正文捕获也已修。 | 实际切页、折叠及缩放的 100 个状态，200 个染色/遮罩采样无几何滞后，16 个切页状态均到达真实 Expander 页面。见 `expander-layout/REPORT.md`；继续随主题和页面动画修复做集成检查。 |
| 2 | **本批折叠布局修复完成。** 修复嵌套高度缓存、自然宽度压过指定宽度，以及 Gallery 示例撑宽窄窗口。 | 同一实际 Gallery 的 98pt 多余空白、49pt 裁切及 29pt 越界归零。补充 RTL、Reduce Motion、内容替换、快速反向和动画中缩放；下方兄弟与滚动范围同步。6 项新测试旧基线 15 处失败；当前 376 项全过。见 `expander-layout/REPORT.md`。 |
| 3 | **本批聚焦文字偏移已修复。** 搜索框恢复原生 cell 所需的编辑器内边距。 | 深浅色、LTR/RTL、中英文、占位/已有文字、1×/2× 的 32 组比较由左移 2pt 变为 0；实际 IME 页面刷新及组合文字缩放保留身份。377 项测试、原生验证、Gallery 和 Release 门禁通过；见 `search-geometry/REPORT.md`。Windows 字形/字体对拍仍保留。 |
| 4 | **本批圆角裁切与禁用文字刷新已修复。** 三种输入控件清除原生布局补偿，Search/Secure 补齐禁用外观通知。 | 64 个状态及 1×/2× 像素检查中，容器内额外 4pt 宽度消失、四角保留；实际 IME 310/270/480pt 声明宽度与绘制相符。两项新测试旧代码 40 处失败，当前 379 项全过，门禁通过。见 `search-chrome/REPORT.md`。 |
| 5 | **框架建议浮层已修；实际 IME 分支仍开放。** AutoSuggestBox 现在跟随祖先滚动/移动，完全裁切时关闭。 | 108 个动态状态通过，380 项测试及门禁通过。实际 IME 隔离探针发现原生行锚点导致 6pt 边框重叠、缩放后需再次发布才回位；尚需验证真实 IMK 传入矩形及回调，不算已修。录屏候选条归属仍待确认，参见 `candidate-popup/REPORT.md`。继续检查屏幕边界、展开候选、选词、关闭、主题；不以模拟 marked-text 代替真实输入法验收。 |
| 6 | **本批已修 NavigationView、IME 页面/标题栏及 FlipView 中断。** | 前者 60 个框架状态、16 个实际 IME 状态、100 个 Gallery 联合状态通过，见 `page-motion/REPORT.md`。FlipView 另有 108 个状态：中断突变 215pt→0，原生内容 0×0 布局修复；最多挂载 5 页，384 项测试及门禁通过，见 `flip-motion/REPORT.md`。真实触摸、高刷/复杂页帧时、Windows 逐帧对拍仍开放。 |
| 7 | **本批 IME 系统主题、ComboBox 浮层与包装层旧内容已修。** | 63 个实际 IME 状态和 21 个 Gallery 状态通过，编辑器、组合文字、焦点、菜单和候选实例保留；显式 light/dark 不受模拟系统切换影响，见 `system-theme/REPORT.md`。另独立复现并修复 24 条旧内容路径，87 状态错误属性 144→0，392 项测试及门禁通过，见 `wrapper-content/REPORT.md`。全局系统设置事件仍需实机验收。 |
| 8 | **本批集成复验完成，实际 IMK 候选定位继续开放。** | 32 个菜单密度、24 个 Switch、32 个返回按钮状态及 57 个实际设置客户端交互状态通过。菜单展开时主题同步，真实 hua 组合输入切换主题后保留编辑器，放大后四处背景采样一致；实际 IME Release 构建通过。见 `integration/REPORT.md`。不把应用级外观信号、CUA 输入或单张到达截图等同于全局系统事件、物理输入或帧时验收。 |
| 9 | **TreeView 批量移动 API、原生点击与延迟加载数据保留已修；完整拖放仍开放。** | 对照 WinUI 归并选择子树、保留顺序、加入计数提示；原生点击实测修复，12 个移动/加载/回滚及 15 个原 Gallery 状态通过。401 项测试和门禁通过。CUA 会话存在鼠标释放早于建立的时序，未收到落点回调；注册类型和 move 掩码已核对，不能标为拖放验收通过。见 `treeview-multi-drag/REPORT.md`。 |
| 10 | **TreeView 附件命中及按下/释放本批已修；AX 展开查询副作用待查。** | 旧回归 33 处失败归零；56 个旧原生状态中 32 处选择错误，修后 72 个状态通过。实际 Gallery 点击、拖出取消及箭头尾部留白验证通过；404 项测试与门禁通过，见 `treeview-pointer/REPORT.md`。AX 读取会让折叠的 Remote 提前出现加载回调，下一批独立追查。 |

## 已处理项与明确边界

折叠卡三项布局缺陷及真实切页后的背景联合复验已经完成，原始失败数据未覆盖，见 `expander-layout/REPORT.md`。搜索聚焦文字左移另已修复，见 `search-geometry/REPORT.md`；圆角裁切及禁用刷新也已复验，见 `search-chrome/REPORT.md`。浮层、翻页、系统主题与联动复验已按序完成本批可验证路径；实际 IMK 候选位置及下列专项验收保持开放。

- `44e71c8`：触控板 `.touch` subtype 被误判为触屏，已修 ComboBox/MenuFlyout 等共享分类。依据及状态图：`../2026-10-31/pointer-popup-density/REPORT.md`。不代表真实触屏验收。
- `b85dcd1`：Switch 按压形变审计；框架默认尺寸正确，IME 的固定 12pt 自定义样式覆盖了动画，已保存并应用可逆补丁。依据：`../2026-10-31/toggle-pressed-review/REPORT.md`。
- `ede65a6`：标题栏返回按钮逻辑和箭头动画修复，见 `titlebar-button/REPORT.md`。IME 的“返回首页”路由仍是应用选择；应用自己的标题栏过渡在第 6 项继续查。
- `497edab`：FlipView 边界手势向父级传递，见 `scroll-chaining/REPORT.md`。手势中途到达边界后的残余滚动传递、完整物理行为仍开放。
- 当前框架批次已通过 404 项测试、原生验证、Gallery 构建和 Release 质量门禁；最近一次实际 IME Release 构建见 `integration/REPORT.md`（TreeView 本批未改 IME 源码）。这些检查不关闭上表尚未复现的问题。实际运行中的旧 IME 不会自动加载静态链接的新框架。

## 不从计划中删除的早期事项

1. **原审计 15 项 + 2 项绘制缺陷**：逐项结果保持在 `../2026-10-30/REMEDIATION.md`，原始 `REPORT.md` 和数据不覆盖。重复刷新、挂载身份、外部重置、快照、样式失效、组合输入策略、ForEach、状态去重、monitor 生命周期、本地化、Gallery 注册和质量门禁继续由回归守护；省略号比例和箭头留白也纳入集成复验。固定 Mica/Acrylic 底色仍不是完整 Windows 材质，字体字形/基线、图标最终观感和真实 IME/VoiceOver 仍未全面验收。
2. **Claude 修改及后续报告**：独立核对见 `../2026-10-30/CLAUDE_REVIEW.md`。6 处 body 简化已验证；“builder 最多 10 个”和“原生控件必须包装”已由编译反例澄清。Xcode Preview、可恢复 snapshot API、可选 URL 导航策略、文档整理和有实测支持的构建优化继续保留；不按推断做破坏性改名或无收益的大拆分。日期耦合 CI 已迁至固定入口。
3. **交接剩余能力**：TreeView 示例/生命周期、批量子树移动 API 及附件按下/移出/释放和 padding 命中已修，仍需 AX 查询副作用修复、完整原生拖放、跨树传输、展开动画和共享 CheckBox 样式精细对照；Collection、CommandBar/MenuBar、AutoSuggestBox、SplitButton 已有独立修复批次，仍保留其报告中的长尾状态与完整行为差距。Calendar/FlipView 的剩余事项见 ROADMAP 的 follow-up，不因已有样例标记为完成。
4. **跨平台与实机**：Windows 同尺寸、缩放、字体与状态对拍，真实触摸、真实中文输入与 VoiceOver 分别验收。MapControl 网络、相机权限场景及 AnimatedVisualPlayer 的 Lottie 支持等已知限制仍保持原范围，不能用样例挂载通过代替。
5. **包装层审查结果**：导航/Undo scope 之后，又独立复现并修复 Accessibility、Lifecycle、Dialog、Command、ControlSizing、SettingsCard 等 24 条旧内容路径，保留 5 条正常路径对照，见 `wrapper-content/REPORT.md`。覆盖当前内置包装器，第三方组合及真实 VoiceOver 仍单独验收。

## 每批的执行与提交

按“实际宿主复现→源码定位/WinUI 对照→保存修复前证据→最小完整修复→行为与动态渲染验证→相关门禁→单独本地提交”执行。背景和折叠布局分别归因，不盲目合为一个问题。已通过的检查仅在新修改或未解疑点需要时重跑；不以新增测试数量判断质量。

应用：`/Users/stars/Downloads/Fluent IME`（无 git）；框架：本仓库。应用修改保存改前哈希与可逆 patch，不覆盖别人的工作，不自动安装/替换正在运行的输入法。每个修复单元单独提交、不推送，保留旧审计原始数据。
