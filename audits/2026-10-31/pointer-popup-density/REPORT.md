# 触控板误用触摸尺寸：ComboBox / MenuFlyout

基线 `cf17631`。由用户提供的 Fluent IME 设置页截图触发，截图保存在 `before/user-screenshot.png`。

## 结论与根因

这是框架缺陷。旧 `FluentInputDeviceTracker` 将鼠标事件的 `.touch` subtype 直接认作触屏。
Apple 的 [Handling Trackpad Events](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html)
说明触控板产生的鼠标事件也采用此 subtype，不能据此推断直接触摸屏幕。

只读核对 Fluent IME 的 `SettingsWindow.choice`：关闭状态是 180×32pt。截图中对应约 360×64 像素，
与 2× 截图一致；展开后约 480 像素宽、96 像素行距，对应框架的 240pt 触摸最小宽及 48pt 行距。
这是对截图的比例推断；可执行复现进一步确认了同一错误几何。

`before/tests.log` 两个新增回归、10 处断言失败。使用 subtype=3 的真实 NSEvent/CGEvent 对象，
旧分类返回 touch；随后打开两项中文 ComboBox/MenuFlyout，结果与触摸分支相同。

## WinUI 依据和修复

本地 `microsoft-ui-xaml-winui3-release-2.3.1`：

- `src/controls/dev/ComboBox/ComboBox_themeresources.xaml:323`：触摸 popup 最小宽 240；335–336 的普通/触摸 Padding 为 `11,5,11,7` / `11,11,11,13`。
- `src/dxaml/xcp/dxaml/lib/ComboBoxItem_Partial.cpp`：按打开设备切换 TouchInputMode。
- `src/controls/dev/CommonStyles/MenuFlyout_themeresources.xaml:259`：Margin `4,2,4,2`；260–261 的触摸/窄 Padding 为 `11,8,11,9` / `11,4,11,5`。
- `src/dxaml/xcp/dxaml/lib/MenuFlyoutItemBase_Partial.cpp:57`：mouse、pen、keyboard 走窄布局。

框架现在将间接触控板鼠标事件归为 mouse；直接触摸事件、明确关联 directTouch 的鼠标序列、
由原生手势识别器记录的 touch 保留触摸语义。没有修改两套既有尺寸。

同时修复输入记录串窗：新窗口不继承另一个窗口的触摸状态；已记录的窗口输入优先于过期 `currentEvent`。
Apple [TN3212](https://developer.apple.com/documentation/technotes/tn3212-adopting-gesture-recognizers-for-sidecar-touch-support)
指出 macOS 27 的控制动作可能在事件分发之后运行，且直接触摸不经 AppKit event monitor。
原生触摸识别器仍需显式记录输入设备，不能依靠 currentEvent 或全局 monitor 推断。

鼠标 release/drag 也分类，覆盖在 mouseUp 打开和首次交互；hover 是指针输入。
实测 `associatedEventsMask` 在 mouseMoved 上抛 Objective-C 异常，已排除该事件类型；
调试中发现的失败日志保留在 `after/initial-mask-validation.log`，最终回归覆盖这个边界。

## 几何结果

两项短中文内容、180×32pt 锚点、标准密度，单位 pt。行距含模板上下 margin。

| 触控板打开 | 修复前 | 修复后 / 鼠标 |
| --- | ---: | ---: |
| ComboBox 行距 | 48 | 36 |
| ComboBox 面板 | 240×104 | 180×80 |
| MenuFlyout 行距 | 44 | 36 |
| MenuFlyout 可绘制行高 | 40 | 32 |
| MenuFlyout 面板高度 | 92 | 76 |

直接触摸分支仍为 48pt ComboBox / 44pt MenuFlyout 行距。MenuFlyout 与 ComboBox 是不同模板，未混用尺寸。
共享分类修复也适用于 CommandBar 溢出、TextCommandBarFlyout、SplitButton 和相关悬停策略。
系统菜单栏和输入法系统菜单仍由 NSMenu 控制，本次没有修改系统菜单尺寸。

## 复现与验收范围

`./audits/2026-10-31/pointer-popup-density/run.sh /tmp/popup-density-new`

`PopupDensityAudit.swift` 使用公开框架 API 和真实面板渲染；Light/Dark × LTR/RTL × mouse/trackpad/keyboard/direct-touch
共 32 张面板图。触控板事件由公开 CGEvent subtype 字段构造；direct-touch 分支通过显式记录模拟识别器交接，
不是物理触屏实测。修复前探针与测试源也保留在 `before/`，原始几何数据见两侧 `metrics.json`。

本次不声称完成物理触屏、真实 VoiceOver 或 Windows 像素对拍。Fluent IME 客户端源码只读检查，
安装中的旧可执行文件仍需重新构建并重新启动，才会加载静态链接的新 FluentKit。

修复后的 32 个渲染状态通过尺寸和非空像素检查，8 对触控板/鼠标图片的完整 RGBA 像素逐字节相同。
`comparison.png` 并排展示修复前后深浅色的 ComboBox 和 MenuFlyout；可见列表行恢复桌面密度，
文字、选中指示条、模板边距和真正的触摸尺寸保持相应模板语义。

最终验收：**345 项测试零失败**；修正错误的旧 touch-subtype 夹具后，原生验证通过，并覆盖触控板次级行菜单与笔输入主命令栏。
Fluent IME 客户端 Release 构建成功（独立 scratch 目录）；其现有 Homebrew librime 构建目标 27.0 高于应用声明的 macOS 13.0，链接器警告保留在 `after/ime-client-build.log`，未将该构建宣称为旧系统兼容性验收。

Gallery Xcode 构建及 Release 质量门禁均通过，日志在 `after/gallery-build.log`、`after/quality.log`。
