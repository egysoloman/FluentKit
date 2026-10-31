# ToggleSwitch 按压形变定点复核

用户提出按下开关是否应缩小/放大。本次核对 WinUI 源码、FluentKit 默认样式和截图应用的自定义样式。

## WinUI 的行为

内部滑块变大，并在按下时横向拉长；轨道不缩放。标准密度下：

| 状态 | 滑块 | 轨道 |
| --- | --- | --- |
| Normal | 12×12pt | 40×20pt |
| PointerOver | 14×14pt | 40×20pt |
| Pressed / 拖动 | 17×14pt | 40×20pt |

松开仍停留控件内时回到 PointerOver；移出后回 Normal。按下不提前切换值，释放确认切换。
尺寸使用 83ms `ControlFasterAnimationDuration`，开/关位置切换使用 167ms `ControlFastAnimationDuration`。

依据本地 `microsoft-ui-xaml-winui3-release-2.3.1`：
- `src/controls/dev/CommonStyles/ToggleSwitch_themeresources.xaml:231`：Normal 的 12×12。
- 同文件 268–279：PointerOver 的 14×14；282–322：Pressed 的 17×14 和左右 3pt 对齐。
- 同文件 507–515：固定 40×20 轨道及两个滑块。
- `src/controls/dev/CommonStyles/Common_themeresources_any.xaml:604`、606：167ms / 83ms。

## 截图应用的偏差

FluentKit 的 `FluentAutomaticToggleStyle` 已实现上述尺寸，`FluentToggle` 负责插值、位置和交互。
原生验证覆盖实际挂载后的 hover/pressed 尺寸、83ms bounds 动画及释放时 167ms position 动画。

Fluent IME 的 `Sources/FluentIME/SettingsWindow.swift:21` 定义了 `SettingsToggleStyle`，
不读取 `isPointerOver`、`isPressed`、`isDragging`，始终返回 `knobDiameter: 12`。
`toggle(...)` 辅助函数又显式安装该样式。它覆盖了默认状态几何，也覆盖了相应状态颜色。
单张静态截图本身不能证明动画缺失；这个结论来自应用源代码以及实际控件复现。

`FluentIME-use-default-toggle.patch` 已应用到输入法应用：删除固定样式及赋值，恢复框架默认样式。
应用源码在修改前重新校验 SHA256，补丁只涉及这两处；修改前后 SHA256 已记录。
应用目录没有 Git 仓库，原文件额外备份在 `/tmp/fluentkit-ime-toggle-before.swift`，补丁可逆向撤销。
框架默认动画无需修改。

## 渲染复核

`ToggleStateAudit.swift` 复制应用的固定样式，使用相同原生 `FluentToggle` 对照默认样式，
实际发送悬停/按下事件并检查图层，覆盖 Light/Dark × On/Off × Normal/Hover/Pressed × 两种样式，共 24 个状态。
默认分别为 12×12、14×14、17×14；应用样式全部为 12×12。静态截图使用 Reduce Motion 固定终态；动画时长由原生验证检查。

这不是物理触屏验收，也不是 Windows 像素对拍。

24 个实际控件状态全部通过断言；`results/light.png`、`results/dark.png` 已人工检查。
应用修改后独立 scratch 的 Release 构建通过（`client-build.log`）；现有 librime 最低系统版本链接警告与菜单批次相同。
当前已安装、运行中的输入法可执行文件没有自动替换；需要将新源码重新打包安装并重启应用后，界面才会更新。

复跑：`./audits/2026-10-31/toggle-pressed-review/run.sh /tmp/toggle-review-new`。
