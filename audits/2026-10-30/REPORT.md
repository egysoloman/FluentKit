# FluentKit 外观与输入性能审计

日期：2026 年 10 月 30 日。

FluentKit 目前还不能按“macOS 上的 WinUI”验收。差距同时存在于渲染更新机制、输入数据同步和视觉基础设施。输入卡顿已在 Release 构建复现；外观偏差也有可定位的来源，包括字体体系、图标接口和 Mica 被映射到原生 Liquid Glass。这些问题需要在框架层处理，逐页调整颜色和间距无法解决。

本次审计记录 15 项框架问题或能力缺口，其中 5 项应优先修复。另外单列 Explorer 接入成本和列表初次布局警告，避免把宿主问题、平台适配和未确定根因混为一谈。本轮不修改运行时实现；上一轮已修复的图片按钮、零高度窗口内容和标题栏无穷坐标不重复作为未修复问题。

## 审计范围与证据

对象是当前工作树中的 114 个 FluentKit Swift 源文件、两个 Gallery、输入与渲染链路、列表、窗口壳、主题和视觉资源。文件清单与哈希见 [manifest.json](manifest.json)。这份清单用于固定被测版本，不代表每个控件的每个状态都已人工操作。

对照基准是仓库中的 `microsoft-ui-xaml-winui3-release-2.3.1`、`WinUI-Gallery-2.9.3` 和用户提供的 Explorer 参考图。WinUI 通用控件默认行为与 Explorer 的应用布局分开判定。CommandBar 默认主命令靠右符合 WinUI，不能把它列为框架缺陷；Explorer 的左对齐需要显式配置。

实测环境为 Apple M3 Pro、18 GiB 内存、macOS 27.2、Apple Swift 6.4。性能脚本同时使用 Debug 库和独立编译的 Release 库。原始结果及脚本均保存在本目录，可运行 `./run.sh` 重新生成 Release 结果。

上一轮的 116 项单元测试和独立验证程序通过，说明现有测试可以通过，但不能据此推导视觉等价、输入性能或数据同步已达标。本轮的外部复现脚本不加入正常测试目标，避免把尚未修复的问题变成项目默认失败的测试。

## 输入与列表性能

测试通过原生文本框修改字符串、发送文本变更通知、等待绑定发布与主队列更新，再执行布局。普通页面和 WindowShell 使用相同输入控件及不变兄弟视图；列表测试使用真正虚拟化的 `FluentListView`。

下表是模拟文本修改后的处理时间，包含绑定发布、视图更新和布局，**不是物理键盘到屏幕的端到端延迟，也不是 Windows 对比跑分**。每个普通树场景执行 30 次文本修改，每个列表场景执行 10 次。它们用于定位框架工作量和可复现的退化，不用于承诺用户帧率。

| Release 场景 | 平均每次修改 | P95 | 每次不变内容更新次数 |
| --- | ---: | ---: | ---: |
| 普通页面与 100 个兄弟视图 | 1.86 ms | 2.35 ms | 100 |
| 相同内容加 WindowShell | 16.35 ms | 31.39 ms | 1,700 |
| 相同内容加 WindowShell 和侧栏 | 40.31 ms | 42.44 ms | 1,700 |
| 普通页面与 1,000 项虚拟列表 | 5.56 ms | 8.49 ms | 18 个可见项 |
| 相同列表加 WindowShell | 64.22 ms | 66.47 ms | 306 次可见项更新 |
| 普通页面与 5,000 项虚拟列表 | 8.10 ms | 9.31 ms | 18 个可见项 |
| 相同列表加 WindowShell | 119.67 ms | 123.74 ms | 306 次可见项更新 |

WindowShell 场景的根 body 每次文本修改只重新求值一次，行更新却放大为 17 次。虚拟列表没有把全部项目实例化：本次修改期间 `rowMakes` 为零，可见项约 18 个。因此“虚拟化存在”与“更新成本合理”是两个不同问题。

同一个 `FluentNativeView` 嵌入实例在普通树的 30 次修改中触发 60 次父视图移除／挂载回调，在 WindowShell 中触发 1,020 次。这里是同一实例反复脱离和重新挂载，不是创建了 1,020 个新对象。

原始结果：[Release 输入](input-release.json)、[Debug 输入](input-debug.json)、[Release 列表](collection-release.json)。列表初次布局还输出了宽度不合法警告，见后文；统计来自预热后的文本修改阶段，但这些数值仍只适用于所记录的测试结构。

## 优先修复的框架问题

### 1 WindowShell 多层宿主重复刷新

**优先级 P1，已实测。** [FluentViewHost.context](../../Sources/FluentKit/FluentDeclarativeCore.swift#L643) 的 `didSet` 会立即更新旧内容。WindowShell 的多层宿主先设置 `context`，随后又调用 `update(content)`，导致同一分支被重复遍历。一个例子是 [FluentWindowContentSurfaceHost.update](../../Sources/FluentKit/FluentWindowShell.swift#L995)，相同模式也出现在窗口共享背景、标题区和页面宿主中。

这与实测 17 倍行更新相符。应提供一次性提交“内容与上下文”的事务，避免通过属性副作用先渲染旧树，再渲染新树；不相关输入不应使稳定兄弟子树重复更新。

### 2 原生视图桥接不支持稳定更新

**优先级 P1，已实测。** [FluentNativeView](../../Sources/FluentKit/FluentDeclarativeCore.swift#L342) 只有创建逻辑，没有实现对应的更新逻辑，落入默认更新失败分支。父容器因此移除并重新挂载原生视图，即使提供的仍是相同实例。

这增加布局和生命周期成本，也给焦点、编辑器、滚动位置及宿主注册带来风险。当前脚本确认的是重复挂载；没有把所有这些风险都当作已发生的数据丢失。应按实例身份复用，并提供明确的原生视图配置更新接口。

### 3 编辑期间的外部绑定值会被旧文本覆盖

**优先级 P1，已实测。** [synchronizeExternalValue](../../Sources/FluentKit/FluentBindingControls.swift#L89) 在输入框有焦点时直接忽略外部值，没有保存待应用值或冲突版本。失焦时再把输入框旧值发布回模型。

复现：输入框内容为 `typed`，外部把模型改成 `external reset`；焦点仍在输入框时，模型与显示值不一致；移开焦点后模型重新变回 `typed`。这会影响清空、加载另一条记录、恢复默认值和表单重置。应区分本地编辑、组合输入和带版本的外部更新，明确冲突策略，避免静默覆盖。见 [editing.json](editing.json)。

### 4 虚拟列表在结构不变时仍重建快照并刷新整节内容

**优先级 P1，已实测并有源码证据。** [FluentCollection.update](../../Sources/FluentKit/FluentCollection.swift#L698) 在结构不变时传入 `reloadingContent: true`。[applySnapshot](../../Sources/FluentKit/FluentCollection.swift#L778) 又重新遍历全部 ID，调用 `reloadSections` 后应用完整快照。

这不会创建全部列表项，但会重复执行与数据量有关的快照操作，并重新配置可见项。WindowShell 又进一步放大其成本，5,000 项场景平均达到约 120 ms。应分离结构、内容、选择和主题更新，只处理实际变化的条目；结构和内容均不变时不应重新应用快照。

### 5 Mica 被优先替换成 macOS Liquid Glass

**优先级 P1，视觉语义偏差，当前环境已实测。** [FluentMaterialView.applyMaterial](../../Sources/FluentKit/FluentMaterialView.swift#L123) 把 `.mica` 与 `.liquidGlass` 一同优先交给 `NSGlassEffectView`。当前系统上两者的 `resolvedBackend` 都为 `nativeGlass`，见 [appearance.json](appearance.json)。较旧系统的 Mica 路径则使用 `underWindowBackground`，Acrylic 使用 `hudWindow`。

这些原生材质有其平台价值，但不能作为 WinUI Mica／Acrylic 已复现的证据。同一配方还会随 macOS 版本改变观感。应把“WinUI 外观配方”和“采用 macOS 原生材质”做成明确选择，为前者建立跨系统稳定的明暗、透明度和活动窗口基准。

## 其余外观与交互缺口

| 问题 | 优先级与证据 | 改进要求 |
| --- | --- | --- |
| 6 排版层级没有沿用 WinUI | P2。`Theme.swift` 的 title 为 22、largeTitle 为 28，且字体提供器只支持整体 scale。上游 TextBlock 资源分别定义 Title 28、TitleLarge 40、Display 68、Subtitle 20。当前标题栏还把上游 Caption 的正常字重改成半粗。 | 建立 WinUI 语义字号、字重、行高及可配置字体提供器；兼容旧命名时给出映射，避免再次引入另一套随意的字号体系。 |
| 7 图标来源接口不足 | P2。MenuFlyout、NavigationItem、TitleBar 等主要接收 `systemImageName`，内部生成 SF Symbols。上一轮补充了按钮 NSImage，但没有解决其他图标槽。 | 统一图标来源与度量，支持符号、字形、位图及路径内容；公开对齐、镜像和着色策略。彩色 Explorer 文件夹属于应用资源，不应声称 WinUI 自动提供。 |
| 8 输入框样式赋值无差别触发布局 | P2。[FluentTextFieldView 更新](../../Sources/FluentKit/FluentControlViews.swift#L232) 每次重设 placeholder 和 style；style 的 `didSet` 总是请求显示及固有尺寸失效。WindowShell 的重复遍历会放大这些成本。 | 将影响尺寸与仅影响颜色的更新分开；使用样式身份／版本或可比较配置避免无效赋值，绘制阶段不要承担属性同步事务。 |
| 9 组合输入缺少提交策略接口 | P2。`EditingAudit` 在 `hasMarkedText == true` 时观察到 `pin` 已进入绑定模型。绑定协调器没有组合输入阶段判断。 | 单独发布组合串并不自动构成 WinUI 不兼容，但框架应提供组合输入事件或提交策略，使搜索、验证和异步请求能等待用户确认文字，而非由应用自行操作 AppKit 编辑器。真实拼音候选窗交互还需人工回归。 |
| 10 ForEach 稳定 ID 仍导致整个排列结构更新 | P2。[FluentForEachHost.update](../../Sources/FluentKit/FluentForEach.swift#L124) 每次移除所有 arrangedSubview，再逐一添加；其中逐项 `contains` 检查具有二次复杂度。 | 对新增、删除和移动做增量更新。ForEach 本来就不是虚拟列表，但稳定 ID 应避免对未变的排列关系做全量操作。 |
| 11 相等状态仍通知全部观察者 | P2。[FluentObservable.value](../../Sources/FluentKit/FluentState.swift#L17) 无条件设置并发布。泛型无法自动比较所有值，现有 API 又未提供比较器或 Equatable 专用路径。 | 提供显式去重策略；验证普通重复赋值不会带来额外 root render，同时保留调用方要求强制发布的能力。 |
| 12 每个输入框各自安装应用级右键监视器 | P2。[FluentTextEditingSession](../../Sources/FluentKit/FluentTextEditing.swift#L231) 初始化就安装 local monitor，直到释放才移除；这与视图是否已挂到窗口无关。 | 通过字段／窗口级路由处理事件，或仅在需要时注册。该项主要影响右键分发和生命周期，不能把它混称为键盘输入卡顿的直接原因。 |
| 13 框架默认文案绕过本地化体系 | P2。`FluentTextEditingSession.textCommands` 的 Cut、Copy、Paste、Select All 等为英文常量；标题栏控制的默认辅助功能文本也有同类问题。已有 `FluentLocalization` 没有贯穿这些控件。 | 默认文案统一解析语言资源，并允许应用替换；中文应用应同时验证可见菜单和辅助功能名称。 |
| 14 Gallery 覆盖元数据缺少可执行对应关系 | P2。121 个目录条目标记为 37 implemented、51 partial、17 platform alternative、3 not applicable、13 missing。37 个 implemented 中有 16 个没有独立的直接 sample 分支；完整 sample switch 共匹配 22 个 ID。 | 这些数字描述 Gallery 元数据，不能当成真实实现完成率。部分控件在外层窗口中已有示范，也不等于有独立验收。应把条目、实际样例、状态矩阵与测试关联，修正过期元数据。见 [coverage.json](coverage.json)。 |
| 15 测试没有覆盖此次主要质量维度 | P2。现有测试有大量有用的行为和几何检查，但快照基线的常规 gate 主要检查尺寸和非空像素变化，缺少输入更新成本、外部重置冲突和原生嵌入身份复用的测试。 | 建立输入更新次数与时延基准、标记文本场景、跨主题状态截图和受控视觉差异检查。功能断言通过不能替代与 WinUI 的外观对照。 |

排版对照来源：[FluentTypography](../../Sources/FluentKit/Theme.swift#L173)、[上游 TextBlock 资源](../../microsoft-ui-xaml-winui3-release-2.3.1/src/controls/dev/CommonStyles/TextBlock_themeresources.xaml)、[上游 TitleBar 标题样式](../../microsoft-ui-xaml-winui3-release-2.3.1/src/controls/dev/TitleBar/TitleBar.xaml#L233)。图标接口可从 [MenuFlyout](../../Sources/FluentKit/FluentMenus.swift#L22) 和 [TitleBar 绘制](../../Sources/FluentKit/FluentTitleBar.swift#L779) 复核。

## 宿主与待定位观察

Explorer 自己也有搜索刷新成本。`BrowserTab` 对 Spotlight 请求有 120 ms 延迟，但文件视图直接订阅 `searchText`，每次变化立即计算可见项、使布局失效，并同时重载列表和图标视图，包括当前未显示的视图。这个成本存在于 Explorer 的 AppKit 接入，不能归到 FluentKit。应按活动视图更新，避免一个输入同时驱动隐藏视图和多次内容刷新。

虚拟列表审计在初次构造／布局时产生 20 行 AppKit 日志，报告 item width 超过 collection view 的可用宽度，见 [collection.log](collection.log)。这确认了临时布局阶段存在问题，但尚未定位到具体是视口变化、滚动条宽度还是约束交付时序。应先补成零宽度、窄视口和带滚动条的独立复现，再修改尺寸计算。

部分基础值已经贴近 WinUI：Body 14、Caption 12，普通输入控件 32 高、4 点圆角，以及 CommandBar 的默认命令区域行为。文件选择器使用 NSOpenPanel／NSSavePanel 是平台服务适配，也不应直接计为控件复刻缺陷。修订应保留这些正确契约。

## 建议实施顺序与验收

第一批先修更新事务、原生嵌入身份和输入绑定冲突，再修列表快照。这一批以当前脚本为基线：一次局部输入不再带来 17 轮兄弟更新，相同原生实例保持父视图身份，外部 reset 不被失焦旧值覆盖，未变化的数据不触发全列表快照。

第二批建立视觉基础：明确 Mica 的语义与实现选择，统一字体和图标来源，再按资源表处理基础控件的 Normal、Hover、Pressed、Focused、Disabled 状态。对照应使用相同字号、窗口尺寸、缩放和浅深主题，不能拿不同页面或 macOS 的原生材质效果证明 WinUI 一致性。

第三批修订 Gallery 和回归门槛。每个宣称可用的控件应有直接可操作的样例及状态证据；输入测试要覆盖短文本、长文本、选择替换、外部清空、撤销、组合输入，以及窗口缩放和主题切换。性能测试应保存原始数据与视图更新次数，避免只依赖一次 wall-clock 结果。

本次没有逐个控件在 Windows 与 macOS 两台机器上做逐像素差异比较，也没有验证全部键盘布局、VoiceOver 操作和真实中文候选窗。这些属于后续验收矩阵；本报告中的实测结论限定在所附脚本及环境，静态能力缺口与待定位观察已分别说明。
