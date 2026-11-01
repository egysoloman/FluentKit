# 用户问题与后续验收计划

更新：2026-11-01。按用户要求顺序推进，保留原审计全部范围。修复一条根因、测试通过或控件类型存在，均不代表整项视觉验收结束。

## 当前处理顺序

| 顺序 | 状态与任务 | 关闭该项需要的证据 |
| --- | --- | --- |
| 1 | **本批背景路径已修并完成联合复验。** IME 材质层与 Gallery 染色层/遮罩分别修复，导航/Undo scope 的旧正文捕获也已修。 | 实际切页、折叠及缩放的 100 个状态，200 个染色/遮罩采样无几何滞后，16 个切页状态均到达真实 Expander 页面。见 `expander-layout/REPORT.md`；继续随主题和页面动画修复做集成检查。 |
| 2 | **本批折叠布局修复完成。** 修复嵌套高度缓存、自然宽度压过指定宽度，以及 Gallery 示例撑宽窄窗口。 | 同一实际 Gallery 的 98pt 多余空白、49pt 裁切及 29pt 越界归零。补充 RTL、Reduce Motion、内容替换、快速反向和动画中缩放；下方兄弟与滚动范围同步。6 项新测试旧基线 15 处失败；当前 376 项全过。见 `expander-layout/REPORT.md`。 |
| 3 | **本批聚焦文字偏移已修复。** 搜索框恢复原生 cell 所需的编辑器内边距。 | 深浅色、LTR/RTL、中英文、占位/已有文字、1×/2× 的 32 组比较由左移 2pt 变为 0；实际 IME 页面刷新及组合文字缩放保留身份。377 项测试、原生验证、Gallery 和 Release 门禁通过；见 `search-geometry/REPORT.md`。Windows 字形/字体对拍仍保留。 |
| 4 | **本批圆角裁切与禁用文字刷新已修复。** 三种输入控件清除原生布局补偿，Search/Secure 补齐禁用外观通知。 | 64 个状态及 1×/2× 像素检查中，容器内额外 4pt 宽度消失、四角保留；实际 IME 310/270/480pt 声明宽度与绘制相符。两项新测试旧代码 40 处失败，当前 379 项全过，门禁通过。见 `search-chrome/REPORT.md`。 |
| 5 | **框架浮层脱锚已修；系统拼音与实际 IME 分支仍开放。** AutoSuggestBox 现在跟随祖先滚动/移动，完全裁切时关闭。 | 108 个动态状态通过，380 项测试及门禁通过。用户已确认录屏蓝色候选条来自 macOS 自带拼音，沿客户端输入上下文/文字矩形另查。Fluent IME 独立探针的 6pt 边框重叠、缩放后需再发布回位是另一条待验 IMK 路径，参见 `candidate-popup/REPORT.md`。不以模拟 marked-text 代替真实输入法验收；搜索建议交互续见第 17 项。 |
| 6 | **本批已修 NavigationView、IME 页面/标题栏及 FlipView 中断。** | 前者 60 个框架状态、16 个实际 IME 状态、100 个 Gallery 联合状态通过，见 `page-motion/REPORT.md`。FlipView 另有 108 个状态：中断突变 215pt→0，原生内容 0×0 布局修复；最多挂载 5 页，384 项测试及门禁通过，见 `flip-motion/REPORT.md`。真实触摸、高刷/复杂页帧时、Windows 逐帧对拍仍开放。 |
| 7 | **本批 IME 系统主题、ComboBox 浮层与包装层旧内容已修。** | 63 个实际 IME 状态和 21 个 Gallery 状态通过，编辑器、组合文字、焦点、菜单和候选实例保留；显式 light/dark 不受模拟系统切换影响，见 `system-theme/REPORT.md`。另独立复现并修复 24 条旧内容路径，87 状态错误属性 144→0，392 项测试及门禁通过，见 `wrapper-content/REPORT.md`。全局系统设置事件仍需实机验收。 |
| 8 | **本批集成复验完成，实际 IMK 候选定位继续开放。** | 32 个菜单密度、24 个 Switch、32 个返回按钮状态及 57 个实际设置客户端交互状态通过。菜单展开时主题同步，真实 hua 组合输入切换主题后保留编辑器，放大后四处背景采样一致；实际 IME Release 构建通过。见 `integration/REPORT.md`。不把应用级外观信号、CUA 输入或单张到达截图等同于全局系统事件、物理输入或帧时验收。 |
| 9 | **TreeView 批量移动 API、原生点击与延迟加载数据保留已修；完整拖放仍开放。** | 对照 WinUI 归并选择子树、保留顺序、加入计数提示；原生点击实测修复，12 个移动/加载/回滚及 15 个原 Gallery 状态通过。401 项测试和门禁通过。CUA 会话存在鼠标释放早于建立的时序，未收到落点回调；注册类型和 move 掩码已核对，不能标为拖放验收通过。见 `treeview-multi-drag/REPORT.md`。 |
| 10 | **TreeView 附件命中及按下/释放本批已修。** | 旧回归 33 处失败归零；56 个旧原生状态中 32 处选择错误，修后 72 个状态通过。实际 Gallery 点击、拖出取消及箭头尾部留白验证通过；404 项测试与门禁通过，见 `treeview-pointer/REPORT.md`。本批发现的 AX 查询副作用已在第 11 项处理。 |
| 11 | **TreeView AX 查询副作用、绑定事件缺失及折叠回调重开被覆盖已修。** | 同一组测试在 d60edee 产生 13 处失败，修后全量 407 项通过。CUA 对真实 Gallery 验证：读取不加载，实际 AX Expand/Collapse 正常；27 个 Gallery 原生状态及相关门禁通过。挂载后绑定变化现在发出事件，初始/重建恢复静默；见 `treeview-expansion/REPORT.md`。完整 VoiceOver 验收仍开放。 |
| 12 | **CheckBox 共享资源、拖出外观、显式主题颜色及原生 AX 暴露已修。** | 同一组 6 项测试在 e0232c4 有 230 处断言失败，修后归零；100 个原生采样的 391 项字段差异归零（含取消复测、不含 TreeView 禁用）。实际 AX 查询和激活通过；413 项测试、原生验证、Gallery 构建及 Release 门禁通过。坐标拖动工具不可用，不计实机验收；见 `checkbox-style/REPORT.md`。 |
| 13 | **RadioButton 原生分组、AX 及显式高对比度颜色本批已修。** | 5 项测试在 c5ad3bd 的 162 处断言失败归零；112 个独立原生状态的 156 项字段偏差归零。CUA 验证独立控件/组容器可查询，同组互斥、独立组保留及外部清空正常；418 项测试、原生验证、Gallery 和 Release 门禁通过。首版探针的跨控件焦点干扰已纠正并保留原始数据；见 `radio-accessibility/REPORT.md`。 |
| 14 | **选择控件键盘提交、取消路径、绑定/组合手势本批已修。** | 同一套最终 11 项测试在旧基线的 41 处失败归零；92 个原生状态中 50 项字段偏差归零。换绑取消的中间策略经 WinUI 源码复核撤回，同实例换绑保留手势、释放写当前模型；最终窗口事件日志证明 Space 在 keyUp 提交，Enter 忽略，数字键盘 +/- 正常。429 项测试及门禁通过，见 `choice-input/REPORT.md`。焦点视觉及同步模型归一化的核查见第 15 项。 |
| 15 | **选择控件默认 HighVisibility 焦点边框本批已修。** | 4 项新测试的 63 处失败归零；96 个原生状态及 128 个像素采样通过（原 104 个像素位置有偏差），433 项测试通过。修复 CheckBox 单层 accent、RadioButton 描边偏移/圆角、HC 角色颜色及圆角更新重新开启裁剪。WinUI 普通焦点不使用 Reveal 的 FocusPress 动画；模型同步归一化已复现，上游也有重入屏蔽，未擅自改为重放。见 `choice-focus/REPORT.md`；祖先边缘挪入、Reveal 和 Windows 实测仍开放。 |
| 16 | **动态页面键盘链及自动重建时的显式循环本批已修。** | 自有窗口启用 AppKit 自动重建；scope/对话框按当前 stack 顺序保持 Tab 循环，保留编辑命令、验证和组合文字，并记录已消费事件的键盘设备。原生 5 项旧失败归零，最终 11 项条件通过；实际 Gallery 已用 Tab/Space 操作 CheckBox/RadioButton，隔离窗口验证循环与对话框。438 项测试、原生验证、Gallery 构建和门禁通过，见 `gallery-keyboard/REPORT.md`。原生程序化焦点、真实 IME/VoiceOver 仍开放。 |
| 17 | **候选取消、辅助按钮顺序及外部更新回调一致性已分批修复。** | 身份变化后的取消与按钮顺序见 `autosuggest-cancel/REPORT.md`（40 个原生状态、118 项字段差异归零）。本批又修复提供器返回旧结果重新弹出、闭包绑定提交时携带过期候选：28 个原生状态的 12 项差异归零，实际窗口验证 ap→Apple→外部 Pear→Enter 提交 Pear/nil 并保留焦点；445 项测试及门禁通过，见 `autosuggest-focus/REPORT.md`。保留外部模型重置优先规则，未为照搬 WinUI 内部字段而恢复旧值覆盖。一次稳定 ID 的 AX 值不一致未再次复现；无需输入重新聚焦的列表开启、完整程序化 Text 契约和 CheckCurrent 式 API 仍开放。 |
| 18 | **客户端普通文本坐标已核查；真实系统拼音候选仍开放。** | 实际设置页与原生输入框共 9 次显式坐标查询，640/600/1000pt 宽度下控件与字符矩形同步移动，设置页 95pt 位移一致、编辑器身份保留。会话未稳定建立系统拼音组合状态，不算候选验收，不据此改定位或关闭第 5 项。录屏无系统候选打开期间缩放过程；外部 IME 源码又有并行变动，结果限于记录构建。见 `system-pinyin/REPORT.md`；继续真实 marked text、跨进程候选、移动/缩放和提交/取消验收。 |
| 19 | **本批已修复常驻滚动条下的尺寸与跳顶问题；硬件事件验收仍开放。** | 修复 AutoSuggestBox、ComboBox、ContentDialog、RefreshContainer、旧 FluentList 及 NavigationView：88 个原生状态的 42 项失败条件归零；实际 Gallery 的 192 个状态（含 Expander/设置折叠卡开合）32 项失败归零。实际 IME 自绘滚动条兼容性、固定最小宽度及视口重排独立修复，105 个状态的 87 项失败归零，完整来源快照 Release 构建通过。452 项测试、原生验证、Gallery 和门禁通过，见 `scroller-layout/REPORT.md`。未改变全局偏好或替换运行中的 IME；真实鼠标插拔仍需验收。横向 Refresh 初始化告警已独立定位到内容宿主的零宽度 mask；自然尺寸布局及内容自主更新的滚动范围已修。新增回归在旧代码 344 处失败，修后相关 14 项及完整 489 项通过，全量测试日志无约束冲突，见 `refresh-initial-layout/REPORT.md`。 |
| 20 | **本批已实现：可选 Tooltip 连续过渡与标题栏接入。** | `.toolTip(..., motion: .continuous)` 同窗口复用 panel，移动、缩放并淡化内容，默认模式不变；标题栏按钮已接入。覆盖打断、退出、窗口生命周期、主题重挂载、降低动态效果、RTL/边缘、动作与还原标签。461 测试、原生验证、Gallery、Release 门禁通过；47 个原生时间样本验证中间帧，见 `tooltip-follow/REPORT.md`。作者未公开源码，属于独立实现。已补 9.31 秒局部桌面合成录屏（`tooltip-follow/recording/`），过渡和阴影可见；真实鼠标悬停、高刷帧时及多显示器验收仍开放。 |
| 21 | **本批通用材质与独立复验完成。** | 局部 → 主题角色 → 预置，Card opt-in、通用背景、窗口/浮层共享配置；动态圆角/材质、Glass 半径、高对比度、workspace 通知及 tint 覆盖前景已修。20 个修后合成状态前景差为 0，背景 tint 保留；三轮配对更新成本接近原基线。472 测试、原生验证、Gallery、Release 门禁通过，见 `material-options/REPORT.md`。真实壁纸采样与平台专项验收仍开放；实际 Gallery 新发现的问题见第 24/25 项。 |
| 22 | **已修浮层选屏、ComboBox 工作区尺寸、TeachingTip 生命周期/根窗口重排；多屏实机继续开放。** | 选屏与尺寸证据见 `popup-screen-placement/REPORT.md`、`combobox-workarea/REPORT.md`。本批 TeachingTip 旧源码 4 条真实回归失败；Release 32 状态中的 12 个卸载/换窗口/关闭异常及 4 处缩放脱锚归零，完整 525 项、原生、Gallery、Release 门禁通过，见 `teaching-tip-lifecycle/REPORT.md`。已更正边界判断：默认允许出根窗口的行为与 WinUI 一致，不能直接判成漏检查。当前只有一块 2× 屏；真实跨屏、热插拔、混合倍率、壁纸/色域、像素描边仍待验收。MenuFlyout 长内容边界与滚动待复现；TeachingTip 完整根边界/可选屏幕约束、ComboBox 完整 non-pannable 填充、touch 循环/半行及编辑模式极小工作区策略继续核查。 |
| 23 | **已修复：Tooltip 接入引起的标题栏三键尺寸回归。** | 用户录屏确认悬停背景高度不一致；32pt 行原生按钮实际为 27/37/36pt。自绘 caption button 清除 SF Symbol 对齐边距后，32/40/48pt 共 9 个原生状态全部准确填满槽位，并重录实际桌面合成视频。见 `caption-pixel-review/REPORT.md`；已在材质批次通过完整门禁。 |
| 24 | **本批修复并验证：ComboBox 面板裁切。** | 原生 bridge/editor 的 750 优先级尺寸把 32pt 宿主压到 23pt；已移除内部 intrinsic metrics 和 editor 对齐边距，较大字体按完整行高增长。9 个原生状态恢复 32pt，实际 Gallery 的 Preset/Liquid Glass 已确认完整显示；476 项测试、原生验证、Gallery 和 Release 门禁通过。见 `combobox-face-layout/REPORT.md`。 |
| 25 | **本批 Toggle 与包装层语义修复并验证。** | 原生 switch 角色、数值状态和通知；标签转发、隐藏/恢复、动态语义分组及 combine/contain 已修。独立窗口和实际 Gallery 操作通过；484 项测试、Gallery、Release 门禁通过，原生完整验证补齐队列同步后连续两次通过。此前多处验证失败及旧基线失败保留在 `toggle-accessibility/REPORT.md`，不以一次重跑掩盖；完整 VoiceOver 仍开放。 |
| 26 | **本批修复并验证：Expander 初始化、动态模板高度和标题裁切。** | 旧 frame 的固定高度 mask 与 stack 最小间距冲突；标题/正文改用自然 Auto Layout 高度，宿主按标题自然高度布局并保留 48pt 最小值。13 项相关回归无约束冲突；完整 487 项、原生、Gallery 和 Release 门禁通过。最终 AppKit 已解析断点 0 命中，24 个 Gallery 状态及实际应用开合复验通过，见 `expander-initial-layout/REPORT.md`。中间版本的动态增长失败已保留；第 19 项 Refresh 已另行修复；第 28 项文字换行保持独立跟踪。 |
| 27 | **本批修复并验证：Toggle 普通键盘提交时机。** | Space 在释放时切换，Return/方向键传给父级；键盘按住不使用鼠标 Pressed 外观。覆盖指针重叠、重复、取消、生命周期、模型更新与回调重入。旧代码 44 个失败断言，修复后相关 17 项与完整 500 项通过；原生、Gallery、Release 门禁通过，CUA 事件记录确认提交在 KeyUp 之后。见 `toggle-keyboard/REPORT.md`。真实硬件、控制器与完整 Windows 验收仍开放。 |
| 28 | **本批修复并验证：设置卡与折叠卡说明换行高度。** | 实际 Gallery 深浅色窄窗口中，说明所需 30pt / 实得 20pt 的截断已修；标签容器收到最终宽度后更新测量，并向祖先传播新高度。24 个 Release Gallery 状态的两处裁切归零，卡片 64→74pt 并在放宽后恢复；动态说明、尾部 action、RTL 与后续行验证通过。完整 502 项测试、原生验证、Gallery 和 Release 门禁通过，见 `settings-description/REPORT.md`。 |
| 29 | **已测得构建耗时差异，待控制变量定位。** | 发布 CI 的全产品 Release 构建耗时 720.12 秒，框架/Gallery 已完成后仍在编译 1.27 万行验证程序；本机 native SwiftPM 的验证程序及框架构建为 123.76 秒。CI 已增加作业预算并复用 Release 产物，所有检查保留；后续分别比较编译器、硬件和构建引擎，评估验证程序的拆分，不能先归因为某一个因素。后续同一 CI 环境的全产品 Release 又测得 309.30 秒，波动本身尚不能证明某个根因；见 `release-0.2.0/REPORT.md`、`popup-screen-placement/previous-batch-ci.log`。 |

## 已处理项与明确边界

折叠卡三项布局缺陷及真实切页后的背景联合复验已经完成，原始失败数据未覆盖，见 `expander-layout/REPORT.md`。搜索聚焦文字左移另已修复，见 `search-geometry/REPORT.md`；圆角裁切及禁用刷新也已复验，见 `search-chrome/REPORT.md`。浮层、翻页、系统主题与联动复验已按序完成本批可验证路径；实际 IMK 候选位置及下列专项验收保持开放。

- `44e71c8`：触控板 `.touch` subtype 被误判为触屏，已修 ComboBox/MenuFlyout 等共享分类。依据及状态图：`../2026-10-31/pointer-popup-density/REPORT.md`。不代表真实触屏验收。
- `b85dcd1`：Switch 按压形变审计；框架默认尺寸正确，IME 的固定 12pt 自定义样式覆盖了动画，已保存并应用可逆补丁。依据：`../2026-10-31/toggle-pressed-review/REPORT.md`。
- `ede65a6`：标题栏返回按钮逻辑和箭头动画修复，见 `titlebar-button/REPORT.md`。IME 的“返回首页”路由仍是应用选择；应用自己的标题栏过渡在第 6 项继续查。
- `497edab`：FlipView 边界手势向父级传递，见 `scroll-chaining/REPORT.md`。手势中途到达边界后的残余滚动传递、完整物理行为仍开放。
- `v0.2.0` 已正式发布，main/tag CI 均通过（491 项测试，1 项平台能力跳过、0 失败），见 `release-0.2.0/REPORT.md`。发布后开关和设置卡补修已推至 main，CI #15 也通过（502 项、1 跳过、0 失败），原始日志见 `popup-screen-placement/previous-batch-ci.log`。浮层选屏 `f0ef72e` 的 CI #16 已通过（512 项、1 跳过、0 失败），原始日志见 `combobox-workarea/previous-batch-ci.log`；ComboBox 约束 `2bdbc31` 的 CI #17 也已通过（516 项、1 跳过、0 失败），日志见 `teaching-tip-lifecycle/previous-batch-ci.log`。本批 TeachingTip 本地完整 525 项、原生、Gallery 和 Release 门禁通过。最近一次实际 IME 来源快照构建及应用补丁见 `scroller-layout/REPORT.md`；未安装或替换运行中的输入法。以上检查不关闭尚未验收的专项，运行中的旧 IME 不会自动加载静态链接的新框架。

## 不从计划中删除的早期事项

1. **原审计 15 项 + 2 项绘制缺陷**：逐项结果保持在 `../2026-10-30/REMEDIATION.md`，原始 `REPORT.md` 和数据不覆盖。重复刷新、挂载身份、外部重置、快照、样式失效、组合输入策略、ForEach、状态去重、monitor 生命周期、本地化、Gallery 注册和质量门禁继续由回归守护；省略号比例和箭头留白也纳入集成复验。固定 Mica/Acrylic 底色仍不是完整 Windows 材质，字体字形/基线、图标最终观感和真实 IME/VoiceOver 仍未全面验收。
2. **Claude 修改及后续报告**：独立核对见 `../2026-10-30/CLAUDE_REVIEW.md`。6 处 body 简化已验证；“builder 最多 10 个”和“原生控件必须包装”已由编译反例澄清。Xcode Preview、可恢复 snapshot API、可选 URL 导航策略、文档整理和有实测支持的构建优化继续保留；不按推断做破坏性改名或无收益的大拆分。日期耦合 CI 已迁至固定入口。
3. **交接剩余能力**：TreeView 示例/生命周期、批量子树移动 API、附件交互及 AX 查询/展开事件已修，仍需完整原生拖放、跨树传输、展开动画；CheckBox 共享资源/AX、RadioButton 分组/AX/高对比度，以及本批选择控件键盘/绑定/组合手势已修。默认选择控件焦点视觉已修，FocusPress 已确认仅用于 Reveal；接续核对祖先裁剪边缘的焦点挪入、RadioButton 内圆描边和组位置描述更新。RadioButtons 同步模型归一化已保留复现，但需结合上游重入保护和 Windows 实测确定契约；独立三态 API、AnimatedIcon 继续保留。Collection、CommandBar/MenuBar、AutoSuggestBox、SplitButton 已有独立修复批次，仍保留其报告中的长尾状态与完整行为差距。Calendar/FlipView 的剩余事项见 ROADMAP 的 follow-up，不因已有样例标记为完成。
4. **跨平台与实机**：Windows 同尺寸、缩放、字体与状态对拍，真实触摸、真实中文输入与 VoiceOver 分别验收。MapControl 网络、相机权限场景及 AnimatedVisualPlayer 的 Lottie 支持等已知限制仍保持原范围，不能用样例挂载通过代替。
5. **包装层审查结果**：导航/Undo scope 之后，又独立复现并修复 Accessibility、Lifecycle、Dialog、Command、ControlSizing、SettingsCard 等 24 条旧内容路径，保留 5 条正常路径对照，见 `wrapper-content/REPORT.md`。覆盖当前内置包装器，第三方组合及真实 VoiceOver 仍单独验收。

## 每批的执行与提交

按“实际宿主复现→源码定位/WinUI 对照→保存修复前证据→最小完整修复→行为与动态渲染验证→相关门禁→单独本地提交”执行。背景和折叠布局分别归因，不盲目合为一个问题。已通过的检查仅在新修改或未解疑点需要时重跑；不以新增测试数量判断质量。

应用：`/Users/stars/Downloads/Fluent IME`（无 git）；框架：本仓库。应用修改保存改前哈希与可逆 patch，不覆盖别人的工作，不自动安装/替换正在运行的输入法。每个修复单元单独提交，保留旧审计原始数据。用户于本轮追加授权推送 GitHub 并发布 Release；0.2.0 按 RELEASING.md 在本地门禁和 main CI 通过后发布。
