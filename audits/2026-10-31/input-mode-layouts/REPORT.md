# 触摸 / 指针布局切换（2026-10-31）

在共享输入基础层（`FluentInputDeviceTracker`）之上，让控件像 WinUI 一样按“打开时的输入设备”
（`InputDeviceTypeUsedToOpen`）选择触摸或指针布局；下一次打开随最新设备切换。

## WinUI 参照

| 控件 | 源 | 指针 / 键盘 | 触摸 |
|---|---|---|---|
| MenuFlyout | `MenuFlyout_themeresources.xaml`、`MenuFlyoutItemBase_Partial.cpp` | NarrowPadding 11,4,11,5（鼠标、笔、键盘） | 默认 11,8,11,9（行高 +8） |
| ComboBox | `ComboBox_themeresources.xaml` InputModeStates | 11,5,11,7，弹出最小宽 80 | TouchInputMode 11,11,11,13（+12），`ComboBoxPopupThemeTouchMinWidth` 240 |
| AppBarButton 溢出 | `AppBarButton_themeresources.xaml` | `AppBarButtonOverflowTextLabelPadding` 0,5,0,8 | `AppBarButtonOverflowTextTouchMargin` 0,9,0,12（+8） |
| TextCommandBarFlyout | `FlyoutBase_partial.cpp` `OnOpening` | 鼠标、键盘：次要命令列表 | 触摸、笔：`InputDevicePrefersPrimaryCommands` |
| FlipView / Pivot / SemanticZoom | 各自 `OnPointerMoved` | 显示导航/缩小按钮 | 不显示 |

## 实现

- `FluentInputDeviceTracker.deviceTypeForCurrentInteraction(in:)`：先识别正在处理的 AppKit 事件（打开菜单的那次点击/触摸），
  否则用窗口最后的设备；因此第一次交互也正确。`isTouch(_:)` 只对鼠标类事件读取 `subtype`（对进入/离开事件读取会抛异常）。
- MenuFlyout：记录打开设备，行距 36 / 44，子菜单继承根菜单；无设备记录的桌面打开保持窄行（对 WinUI 默认的偏离，见下）。
- ComboBox 弹出层：行高 36 / 48，触摸时最小宽 240，选中项居中计算随行高变化。
- CommandBar 溢出：行高 40 / 48。
- 文本上下文菜单：按事件识别设备，只有触摸、笔使用主命令栏。修正了此前“非右键即主命令栏”的判断（Ctrl+左键是鼠标）。
- FlipView：触摸不显示导航按钮。

## 验证（结果在 `results/`）

- `swift test -Xswiftc -warnings-as-errors`：**240 项通过**，新增 `InputModeLayoutTests` 5 项。
- 原生验证：把原来用左键模拟“偏好主命令”的步骤改为合成真正带触摸子类型的事件后通过。
- 质量门禁、完整 Gallery 构建通过。
- 过程中发现：对进入/离开事件读取 `subtype` 会抛 `NSInternalInconsistencyException`，已统一改用 `isTouch(_:)`。

## 与 WinUI 的偏离与局限

- WinUI 在“无设备”（程序化打开）时使用默认（较宽）内边距；macOS 桌面上这里保持窄行。
- ComboBox 的触摸“轮盘”模式（`m_bShouldCarousel`）和可平移弹出层未实现。
- 布局在打开时决定，打开中的弹层不随设备变化实时重排（与 WinUI 一致）。
- 未在真实触摸屏上验证。
