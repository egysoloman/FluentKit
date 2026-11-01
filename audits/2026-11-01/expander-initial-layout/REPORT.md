# Expander 初始化约束与自定义标题高度

基线 `2ac8d0b`；运行时与回归修复提交 `f36d9c5`。继续 FOLLOW-UP 第 26 项；本批没有修改或替换 Fluent IME。

## 独立复现

现有 ComboBox 容器回归再次在 `FluentDisclosure.swift:342` 报告约束冲突，但 XCTest 仍判通过，见 `before-test.log`。因此本批没有把普通测试退出码作为告警消除的证据。

`InitialLayoutAudit.swift` 单独创建 Expander，其正文包含两个相隔 12pt 的行。挂载时正文尚未得到 frame，`translatesAutoresizingMaskIntoConstraints` 已变成 true，产生 required 的 `height == 0`。标题栏 `isExpanded` 的外观更新立即调用 `layoutSubtreeIfNeeded`，把整个尚未分配尺寸的布局树交给求解器；0 高度无法容纳两行之间的 required 最小间距。

- `before-debugger.log` 保留了实际约束：`NSAutoresizingMaskLayoutConstraint ... height == 0` 与 `NSStackView.Stack.Min ... >=12`，以及 AppKit 打破间距约束的记录。
- 首次尝试的旧断点名称没有解析；依照当前 AppKit 日志提示改用 `LAYOUT_CONSTRAINTS_NOT_SATISFIABLE`。`before-backtrace.log` 在这个已解析断点停止，调用栈明确经过 header 外观刷新、isExpanded setter、host applyState 和构造函数。
- 初版修复的探针见 `after-debugger.log`；最终实现重新运行相同探针，同一个 AppKit 断点解析成功、命中为 0 且正常退出，见 `reproduction-final/debugger.log`。
- 初版对比 `before-geometry.json` / `after-geometry.json` 的最终宿主均为 380×141pt。这是初始布局期间的缺陷，最终几何本来就能恢复，不能用到达截图替代初始化检查。

## WinUI 对照及第二处偏差

固定源码 `microsoft-ui-xaml-winui3-release-2.3.1/src/controls/dev/Expander/Expander.xaml:107–114` 使用自动行高和 `MinHeight`，默认资源 `ExpanderMinHeight` 为 48。FluentKit header 已测量自定义内容，但宿主实际高度及正文起点一直固定为 48pt，导致 72/104pt 自定义标题被压缩或裁切。

新回归在未修改的运行时代码上产生 14 项高度/正文位置断言失败，见 `before-new-tests.log`。这个旧日志还包含一个只观察 NSStackView.layout 的早期探针；该探针未能捕获求解器先于 layout 的冲突，最终测试已用嵌套设置卡重排用例替换，初始化冲突由上面的 AppKit 断点独立验证。

## 最终修复

- 标题和正文由 Auto Layout 保持自然高度，去掉其原先从 frame 生成的固定 autoresizing mask 高度。宽度和位置由外层分配，标题垂直居中，正文保留 16pt 内容边距；高度不再与尚未更新的父级 frame 锁死。
- 标题栏外观刷新只标记布局失效，不再直接求解整个子树；初始展开也等待父级分配区域。
- 宿主自然高度、实际标题高度及向下展开的正文起点，共用标题测量结果；48pt 保留为最小值。
- 标题的 16pt 起始边距和 60pt chevron 保留区按 RTL 镜像；使用物理左右锚点，避免显式镜像与语义锚点重复翻转。文本以 AppKit alignment rect 对齐该边界。

没有降低 stack 间距约束优先级，也没有静音 AppKit 日志。远端宽度边界采用框架已有的 999 优先级规则，允许尚未分配尺寸时的临时边界；内容自己的自然高度继续成立。

初版采用预先设置自然 frame、避开零尺寸布局，已通过原始初始化探针和普通 Gallery 状态；随后新增“已挂载的多行标题间距 4→80pt”检查，仍在旧高度的 mask 上复现冲突。仅删除 header 强制布局会把冲突推迟到父级求解；临时重新测量同样会遇到旧 mask。对应原始日志为 `header-growth-before.log`、`after-tests-complete.log`、`after-tests-allocation.log`。最终采用上述自然高度布局；未把初版测试通过当作全部完成。

## 验证

- 最终 13 项相关测试通过，且 `check_test_diagnostics.py` 确认日志中无约束冲突，见 `targeted-tests-final.log`。
- 新测试覆盖自定义标题 72→104→24pt 更新（最后回到 48pt 最小高度）、上下展开、折叠/恢复，以及嵌套设置卡视口和后续行移动、关闭期间更新后重开。
- 额外覆盖标题/正文两种模板的多行间距 80→4→120pt 动态增长，LTR/RTL 的标题边距及内容完整包含关系。
- 最终完整 XCTest 487 项、0 失败，原生验证 PASS，Gallery 构建成功，Release 更新计数、身份、外部重置、字体和材质门禁通过。见 `full-tests-final.log`、`native-validation-final.log`、`gallery-build-complete.log` 与 `quality-run-final.log` / `quality-final/`。没有 `final` / `complete` 后缀的早期门禁属于中间实现。
- 使用最新链接产物重新运行实际 Gallery 页面源码驱动，深浅色、宽窄、上下展开、反向打断和外层重开共 24 状态，几何断言 0 失败、日志无约束冲突，见 `gallery-final/`。这里是同一页面代码的独立窗口；另外用 CUA 重启最新 Gallery 应用，搜索 Expander，验证了内层折叠、外层关闭/重开、内层状态保留及后续卡片移动。操作记录见 `gallery-cua-notes.md`。
- 视觉检查 `gallery-final/images/dark-narrow.png` 时观察到外层设置卡的长描述疑似只显示首行，末尾 acceptance matrix 不可见。第 28 项单独追踪文字换行/高度问题；上述 24 状态断言覆盖容器几何，不据此声称所有文字均完整可见。
- 最终全量日志仍检出原第 19 项 `testHorizontalRefreshContentFollowsLiveScrollerStyle` 警告，见 `full-constraint-diagnostics-final.log`。Expander 相关检查无冲突；本批不把全量 XCTest 通过称为全仓库约束诊断通过。

重跑初始探针：`zsh run-initial.sh <SwiftPM products 目录> <新的输出目录>`。它要求 AppKit 断点确实解析、0 次命中且进程正常退出。

重跑 Gallery：`zsh run-gallery.sh <SwiftPM products 目录> <新的输出目录>`。使用当前 Gallery 源码与已有 `../expander-layout/ExpanderGalleryAudit.swift` 驱动，历史原始数据不覆盖；中间可执行程序放在临时目录。

第 19 项横向 Refresh 初始化警告保持独立跟踪。真实 VoiceOver、IME 候选、物理触摸、多显示器与 Windows 像素对照仍未由本批验证代替。
