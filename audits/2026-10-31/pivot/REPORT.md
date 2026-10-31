# Pivot 实现（2026-10-31）

此前 Gallery 目录中 Pivot 为 **missing**。本批新增公开 `FluentPivot`，覆盖状态记为 **partial**。

## WinUI 参照

本地 `microsoft-ui-xaml-winui3-release-2.3.1`：

- `src/controls/dev/CommonStyles/Pivot_themeresources.xaml`：标题项高 48、24pt SemiLight、
  字距 -25、左右内边距 12；选中下划线高 3、距底 2、圆角 1.5、`AccentFillColorDefault`；
  标题 14pt Bold，边距 12,14,0,13；PivotItem 边距 12,0,12,0；导航按钮 20×36、上边距 6、
  12pt 箭头；Base 色阶前景（未选 60%、悬停/按下 80%、选中 100%、禁用 40%）；
  `UnselectedLocked` 平移 40 并隐藏，与 Unselected 之间 0.33s 过渡。
- `src/dxaml/phone/lib/Pivot_Partial.cpp`：
  - `ShouldUseStaticHeaders`：关闭 `IsHeaderItemsCarouselEnabled` 时始终静态；否则全部放得下才静态。
  - `ShouldWrap`：仅动态（轮播）标题循环。
  - `UpdateVisualStates`：指针在标题上时显示导航按钮；轮播两侧都显示；静态且被裁剪时按首末项
    显示一侧；锁定时都隐藏。
  - `OnHeaderKeyDown`：左右键（RTL 互换）、Home、End；`OnKeyDownImpl`：Ctrl+Tab、
    Ctrl+Shift+Tab、Ctrl+PageUp/PageDown。
  - `PivotAnimator`：飞出 83ms 平移 7px（线性）+ 67ms 透明度；飞入 767ms 平移 20px +
    333ms 透明度，曲线 (0.1,0.9)-(0.2,1.0)；轮播标题位移 83+767ms。
  - 锁定时不响应标题点击和任何导航。
- `src/dxaml/xcp/components/pivot/PivotCurveGenerator.cpp`：`GetHeaderShiftOffset`，用于
  关闭轮播且标题被裁剪时，按选中项前后剩余空间比例平移静态标题。

## 实现

- `Sources/FluentKit/FluentPivot.swift`：声明式 `FluentPivot(data, selection:, title:,
  isLocked:, isHeaderItemsCarouselEnabled:, leftHeader:, rightHeader:, onSelectionChanged:,
  header:, content:)` 与原生 `FluentPivotControl`。
- 绑定：初始值和数据缩短时归一化并写回；替换绑定后丢弃旧绑定已排队的通知；初始选择不触发
  `onSelectionChanged`。
- 被中断的切换动画会先收尾，不会残留旧页面；Reduce Motion 下直接切换。
- 无障碍：控件为 tab group，标题项为可按下的单选按钮并带选中值，锁定隐藏的标题不对外暴露。
- 新增本地化字符串 Pivot / Previous / Next（en、zh-Hans、zh-Hant）。
- Gallery 新增直接示例（含锁定开关），Gallery 注册检查断言挂载了 Pivot。

## 验证（`run.sh`，结果在 `results/`）

- `swift test -Xswiftc -warnings-as-errors`：**175 项通过**，新增 `PivotRegressionTests`
  10 项（[tests.log](results/tests.log)）。
- [质量门禁](results/quality.log) 通过；[Gallery 注册检查](results/quality/GallerySampleAudit.json)
  中 Pivot 在 light/dark/RTL 下挂载成功。
- [截图审计](results/visual.json)：light/dark/RTL × 静态（520pt）/轮播（300pt）× 6 个状态
  （初始、悬停、选中、边界、锁定、禁用），共 36 张；按钮可见性、循环、锁定断言全部通过。
- [原生验证](results/native-validation.log)：`FluentKitValidation: PASS`。
- [完整 Gallery 构建](results/xcode-build.log)：`BUILD SUCCEEDED`，关闭签名。

人工查看了 light 静态选中、dark 轮播悬停、RTL 静态锁定三张截图。

## 局限（因此为 partial）

- 没有触控板手势平移（WinUI 的 ScrollViewer 拖动/轻扫及其中间态）；切换只通过点击、键盘和按钮。
- 轮播标题用一次 850ms 位移动画近似，未复刻 WinUI 拖动过程中的标题联动曲线。
- 未实现 `HeaderFocusVisualPlacement.SelectedItemHeader`、PivotItemLoading/Loaded 等事件、
  标题模板（只支持文字标题）。
- SemiLight 使用 AppKit 最接近的系统字重；未与 Windows 逐像素对照，VoiceOver 未实测。
- 修复前日志不适用：此前没有 Pivot 实现。
