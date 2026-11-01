# FluentKit 0.2.0 发布候选验证

用户已明确授权推送 GitHub 并发布 Release。遵循 RELEASING.md：版本/安装示例/CHANGELOG 一致，本地门禁通过后推 main，等待该提交的 CI 成功，再创建 annotated tag 并发布 latest Release。初始本地候选的最后运行时修改为 `4fc002b`，发布准备提交为 `c6c5cab`。远端随后发现不同工具链下的编译问题，修复与后续验证见下节。

## 本地门禁

- Debug build：通过（`debug-build.log`）。
- XCTest：489 项，0 失败（`tests.log`）。约束诊断扫描：none（`constraint-diagnostics.log`），此前 Refresh 告警已独立修复。
- 交互桌面原生验证：PASS（`native-validation.log`）。
- 所有产品 Release build：通过，115.19 秒（`release-build.log`）。
- Xcode Gallery：BUILD SUCCEEDED（`gallery-build.log`）。
- Release 工作计数/身份/外部重置/字体/材质与样例门禁：通过（`quality-run.log`、`quality/`）。
- Refresh 独立原生断点探针：已解析、0 命中、正常退出（`../refresh-initial-layout/after/`）。

## 视觉检查范围

重新生成并查看 980×680 的 Controls Light/Dark 和 Accessibility RTL 三张 Gallery 图像，并逐张查看同名 `.snapshots/` 历史图作对照。当前标题字号、图标和固定材质配方较历史图变化，滚动条样式也不同；已确认所选状态未出现空白页面、错侧的 RTL 导航或正文/Expander 相互重叠。候选图片在本目录，历史基线保持原样，不把这些有意差异称为像素比对通过。Release 样例门禁另包含 Light/Dark/RTL 挂载；质量工具生成的交互状态图像见 `quality/visual/`。

这不是 Windows 对拍，也不是所有控件的动态/实机验收。已知 Toggle 键盘提交时机、窄窗设置卡描述、多显示器及真实输入/辅助功能任务仍在 FOLLOW-UP；Release notes 明确保留这些限制。

`RELEASE-NOTES.md` 是要发布的正文。远端 CI 与 Release 的结果以该提交对应的 GitHub 运行和标签为准，不用本地通过替代远端门禁。

## 首次远端 CI 与兼容性修复

[main CI #8](https://github.com/egysoloman/FluentKit/actions/runs/41279385026) 在 macOS 26.6.2 / Swift 6.3.3 的 Debug 构建失败；本机是 macOS 27 / Swift 6.4。完整日志保存为 `ci-first-failure.log`。Release 标签和发布操作尚未进行。

1. CommandBar 的局部 `primaryWidth` 与方法同名，旧编译器将闭包中的调用解析为变量；改名为 primaryControlsWidth。
2. Capture 的局部 session 声明在一个使用同名成员的闭包之后；将快照声明移到使用前，避免旧编译器捕获尚未声明的局部变量。
3. 仅有运行时 `#available(macOS 27)` 不足以在旧 SDK 编译新的手势属性。保留运行时 OS 检查，使用公开 Objective-C setter 的 responds 检查及 KVC 配置三个属性。没有通过更换 runner 或关闭门禁回避问题。

修改后本机相关 40 项测试通过（`compatibility-tests.log`），包括 macOS 27 真实 recognizer 的触摸数量与取消配置读取。旧系统上的该测试仍按原有条件跳过。后续主分支 CI 必须成功后才能按流程发布；以对应 GitHub 运行结果为准，不把此处本地结果当作远端通过。

## 第二次远端 CI 与环境回归

[main CI #9](https://github.com/egysoloman/FluentKit/actions/runs/41279715448) Debug 编译通过，测试运行 489 项、1 跳过、55 个失败断言。完整日志为 `ci-second-failure.log`，没有忽略这些失败或降低 CI 门禁。

- 独立使用 native SwiftPM Release 产物复现了中文资源查找失败：目录为 `zh-hans.lproj` / `zh-hant.lproj`，大写 script 候选的 Bundle 查找返回 nil。现在先匹配 bundle 实际 localization 名称，新增大小写回归。
- 将本地 Refresh 回归强制为 legacy scroller，独立复现 16 个失败；内容缩短后 scroller 隐藏，但内容仍保留旧视口宽/高（17pt 差）。共享 FluentViewportScrollView 现在合并并异步通知尺寸变化，避免在父布局中同步设置的 needsLayout 被清掉。扩展测试覆盖 overlay/legacy × 四方向 × LTR/RTL × 内容增减，不调用合成 scrollWheel。
- ToolTip presentation 的 coordinator 原来再次读取全局减少动态效果设置，覆盖了调用方已经解析的 render context。现在仅由传入策略控制；显式减少动态效果仍立即完成。
- 测试修正：动画测试明确选择启用动画；TimePicker 检查一个物理像素而非假定 Retina 的 0.5pt；trackpad 绘制测试保留窗口坐标，CGEvent subtype 分类仍由独立测试验证。正向异步结果改为有上限等待实际 UI/回调，保留结果断言。新等待辅助方法最初误等了三处不应有弹层的场景，原失败日志保留，随后改等其真正结果，相关 30 项通过。
- 焦点问题在本机两个构建引擎都未复现，保留原行为断言，并补充失败时的几何、acceptsFirstResponder、canBecomeKeyView 和系统键盘模式数据。需要下一次远端结果继续定位，不宣称已解决。
- 质量脚本独立复现旧布局下的 no such module。现在自动识别 Swift Build 与 native SwiftPM 的 module/object 位置，并可显式选择引擎复现。

本地相关运行时 32 项通过，native 引擎焦点 6 项通过。全部原始验证记录在 `environment-compatibility/`。发布仍等待远端全绿。

修复后的 native Release 质量工具全通过，记录在 `environment-compatibility/native-quality*`；Swift 6.4 的 native 引擎弃用提示属于刻意选用旧引擎的工具提示。`locale-before.log` 与 `locale-after.log` 分别来自修复前后静态链接的独立探针；相同资源包由 Copy/Copy 恢复为 复制/複製。

## 第三次远端 CI：焦点差异定位

[main CI #10](https://github.com/egysoloman/FluentKit/actions/runs/41281210290) 的失败减少为 13 个断言（490 项、1 跳过），完整日志为 `ci-third-failure.log`。中文资源、legacy scroller、motion 和之前的其余回归已经通过。

焦点诊断显示 enabled/visible、acceptsFirstResponder 均正常，所有 FluentButton 的 canBecomeKeyView 为 false；系统 fullKeyboard=false。本机同一用例在两种构建引擎均通过，说明此前不能只依据本机通过得出结论。现在 FluentButton 明确实现自己的 Tab 停靠资格，保留可见性、窗口输入能力、禁用与 refusesFirstResponder 限制；README/CHANGELOG/Release notes 已写出这一行为变化。[Apple 的 canBecomeKeyView 合约](https://developer.apple.com/documentation/appkit/nsview/canbecomekeyview) 列明可见、窗口支持键盘输入、接受 first responder 三项前提。新增测试保护主动退出/隐藏/禁用等约束。

另一个 AutoSuggest 失败是清除后第二次输入仍在固定 180ms 后读取弹层；已同样改为限时等待可见结果，没有删除其内容断言。修改后相关 8 项本地测试通过（`focus-policy-tests.log`）。

此前环境修复候选 c71ce1e 的 native SwiftPM 全量 490 项测试、无约束告警、全产品 Release、Xcode Gallery、原生验证均通过，记录为 `c71-*.log`。这些是对应候选的证据；后续按钮焦点提交仍须等远端 CI 通过。


## 第四次远端 CI 与最后的异步观察修正

[main CI #11](https://github.com/egysoloman/FluentKit/actions/runs/41281760024) 执行 491 项、1 跳过，剩余 3 个失败断言，原始记录为 `ci-fourth-failure.log`。焦点回归全部通过。剩余两条 AutoSuggest 断言仍在 150ms 防抖后固定等待 190ms，改成有 2 秒上限等待实际回调；观察 body 的用例等待实际的状态标签更新，继续检查原输入框实例、查询文本与候选选择。

导航用例原来只统计红色，没保存失败时图像，无法区分原页面已变为绿色与真实空白，因此不能对当次失败做确定归因。现在额外检查中断时实际保存的合成图像含可见旧场景、尺寸正确、新动画起始透明度为 1；同时保留呈现树的像素覆盖断言，识别三个合法页面颜色，避免把绿色/蓝色当作空白。没有修改导航运行时。

更新用例过程曾误等一个不会发生的取消状态更新（示例只在选中候选时更新该标签）；这次本地失败保存在 `final-observation-tests.log`，修正后 AutoSuggest 24 项、导航 1 项通过，另复验实际 body 标签更新用例 1 项通过，见对应日志。

本批仅改测试和文档，运行时代码仍为 `f369c94`：本地 native SwiftPM 全部 491 项零失败、无约束诊断；全产品 Release、Xcode Gallery、原生验证与 Release 质量门禁均通过，记录为 `final-491-tests.log`、`f369-*.log` 和 `f369-quality/`。以上是本地证据，发布仍需等待最新 main CI 全绿；真实 Windows 逐帧对拍和实机输入验收仍未完成。
