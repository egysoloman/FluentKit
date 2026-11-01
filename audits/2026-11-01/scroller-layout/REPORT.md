# 滚动条样式切换与可用视口审计

基线：`032862c`；框架修复提交：`c25e062`。日期：2026-11-01。未修改系统滚动条偏好，未安装、替换或停止正在运行的 Fluent IME。

## 结论

确认并修复了框架中 6 条路径的问题：AutoSuggestBox 建议列表、ComboBox 列表、ContentDialog、RefreshContainer、旧 FluentList、NavigationView 侧栏。AppKit 切换到 legacy 常驻滚动条后，本机可用宽度或高度减少 17pt；部分手动布局只响应外部 frame，遗漏了内部 clip view 的变化。旧 FluentList 则在重新排布时把 100pt 滚动位置重置为 0。

实际 IME 设置页另有应用层原因：自绘 SettingsScroller 未声明支持 overlay，导致显式请求 overlay 也被 AppKit 保持为 legacy；页面还沿用 550pt 最小宽度，且未响应滚动条出现/隐藏后的视口变化。600pt 窗口的常规页测得右留白只有 9pt，预览页为 26pt。这些是尺寸/留白异常，原数据没有证明所有页面都发生了文字裁切。

| 复现 | 每个版本的状态数 | 修前失败条件 | 修后失败条件 |
| --- | ---: | ---: | ---: |
| 11 类原生控件，LTR/RTL，overlay→legacy→overlay→legacy | 88 | 42 | 0 |
| 实际 Gallery Expander 页面，浅/深色、LTR/RTL、720/1280pt，含设置折叠卡开合 | 192 | 32 | 0 |
| 实际 IME 设置源码，7 个页面、600/640/1100pt、初始及双向样式切换 | 105 | 87 | 0 |

这些数字是独立条件的失败数，不是框架缺陷数量。原生控件中有 20 个状态的文档横向尺寸错误、16 个状态的行超出可用宽度、6 个状态丢失滚动位置；Gallery 的 32 项为侧栏文档超宽。IME 为 42 次 overlay 请求被拒绝、45 次留白不符合目标。完整判定见 [comparison.json](comparison.json) 和 [check-results.py](check-results.py)。

## 修复方式

- 内部 `FluentViewportScrollView` 在 AppKit `tile()` 后比较 clip 大小，仅在大小变化时通知所属控件重排。滚动位置变化本身不触发这条父级布局路径。搜索建议、ComboBox、对话框、RefreshContainer 和导航侧栏复用它。
- ContentDialog 为常驻滚动条保留空间，内容按实际可用宽度排布；标题仍使用完整标题区域。
- FluentList 让 clip view 同步调整集合文档宽度，并按当前视口解析行宽，避免延迟生效的宽度约束让 AppKit 先用过期尺寸重新计算布局、跳回顶部。
- NavigationView 的主列表、紧凑图标列和页脚使用同一可用宽度，避免右侧内容伸入滚动条区域。
- IME 的自绘滚动条声明 overlay 兼容，但仍允许系统选择 legacy。设置页按视口重排，去掉 550pt 硬下限；标签和首页导航项按可用宽度收缩。普通页面保留 20pt 右留白，预览页保留 24pt 以容纳候选条阴影；滚动位置保持不变。

应用层只改了两个文件，相关补丁保存在 [ime-scroller-fix.patch](ime-scroller-fix.patch) 与 [ime-compile-fix.patch](ime-compile-fix.patch)。后者修复当前应用源码中 `CandidateGridDocument` 继承 `final IMEFlippedView` 导致的编译错误，只移除基类的 `final`。修改前核对文件散列，并在写入前再次检查，保留了应用的并行改动；没有整文件回退。

## 验证及来源

- 最终运行时代码：452 项测试通过，原生 `FluentKitValidation` 通过，Gallery Debug 构建通过，Release 质量门禁通过。之后为测试宿主明确初始 frame，7 项滚动条测试再次通过；横向 Refresh 挂载告警仍存在，见下文。
- 实际 Gallery 使用导航协调器进入 Expander 页面，分别激活普通 Expander 与设置折叠卡，并断言高度确实改变。最终数据等待 0.6 秒越过动画再采样；开合后尺寸稳定，没有重现此前担心的持续高度漂移或横向越界。
- 实际 IME 的独立探针使用相同设置源码、独立 bundle ID 和临时 Rime 用户目录。外部源码在本轮期间发生并行变化，因此保留了初次结果，并重建 `ime-before-current` 基线。修后 105 个状态的样式、留白、右边界和滚动位置均满足检查。
- IME 完整 Release 构建在来源散列锁定的临时副本中通过。保留了本机 librime 为 macOS 27 构建、应用部署目标为 macOS 13 的链接警告；这不证明旧系统运行兼容性。
- 所有带原生窗口的探针和测试串行运行；未向 `NSScrollView.scrollWheel` 注入合成事件。构建可并行。执行结果见 [verification-steps.json](verification-steps.json)、[fixture-verification-steps.json](fixture-verification-steps.json)、[gallery-settled-verification.json](gallery-settled-verification.json)。

Apple 的 [preferredScrollerStyle](https://developer.apple.com/documentation/appkit/nsscroller/preferredscrollerstyle) 文档说明，偏好可随系统设置和输入设备变化，AppKit 会更新 scroll view 并重新 tile。SDK `NSScroller.h:44–54` 明确说明，自定义子类默认可能不兼容 overlay，需要声明兼容。本地 WinUI 参考 `microsoft-ui-xaml-winui3-release-2.3.1/src/controls/dev/ScrollView/ScrollView.xaml:143–163` 中，ScrollPresenter 跨越滚动条所在的网格区域；AppKit legacy 会占用真实空间。本批修复适配这个差异，没有靠强制全局 overlay 隐藏问题。

## 保留的中间数据与验收边界

- `probe-initial` 的部分控件视口为零，不能作通过/失败证据；修正宿主尺寸后得到 `before-basic`，再补入对话框成为最终 88 个状态。
- Gallery 的 `gallery-catalog-*` 未真正导航到 Expander；`gallery-inner-only-*` 没有成功激活自定义设置卡头部；`gallery-intermediate-animation-*` 在动画中途采样。均保留原始结果及对应 fixture，最终结论仅使用 `before/gallery-results.json` 与 `after/gallery-results.json`。
- 首次测试编译使用了错误的 FluentList 构造方式；首次完整 IME 副本遗漏 Tests，导致 SwiftPM 错误地探测源码目录。这两项是本次探针/副本问题，已纠正，失败日志保留，未归为产品缺陷。
- **横向 RefreshContainer 的初始挂载仍会在测试中报告一次约束冲突，修前修后均存在。尚需区分宿主 fixture 与框架原因，不能用当前尺寸断言通过代替解决该告警。**
- 尚未进行真实鼠标插拔、修改全局“显示滚动条”偏好、触摸设备、Windows 像素对拍或 VoiceOver 验收；本轮直接驱动的是 AppKit 的实际样式 setter。
- 系统拼音 marked text/跨进程候选验收仍按 `system-pinyin/REPORT.md` 保持开放。当前运行中的旧 IME 不会自动加载新源码；应用结果仅对应记录的来源散列。

## 复现入口

```sh
swift test --scratch-path /tmp/fluentkit-repair-tests -Xswiftc -warnings-as-errors --filter ScrollerLayoutRegressionTests
zsh audits/2026-11-01/scroller-layout/run-native.sh "$TMPDIR/fluentkit-quality-release/out/Products/Release" /tmp/scroller-native
zsh audits/2026-11-01/scroller-layout/run-gallery.sh "$TMPDIR/fluentkit-quality-release/out/Products/Release" /tmp/scroller-gallery
python3 audits/2026-11-01/scroller-layout/check-results.py
```

IME 探针先构建当前 `FluentIMECore`，再通过 `build-ime.sh <独立 app 路径> <输出目录>` 编译；脚本在前后检查来源散列。完整应用构建的来源清单、临时副本路径和日志位于 `ime-full-build/`。修前框架产品在本机另存为 `/tmp/fluentkit-scroller-baseline-products`，不随仓库分发。
