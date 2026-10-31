# Pivot 手势与触控（2026-10-31）

在 `770f248`（Pivot 首版）基础上补齐交互式平移。Pivot 覆盖状态仍为 **partial**。

## WinUI 参照

- `src/dxaml/xcp/components/pivot/PivotStateMachine.cpp`：平移结束后，最终位置与起点相差超过
  四分之一个分区则进入 `InFinishTransition`，否则 `InSnapBackInertial`；轻扫动画上限 0.4s。
- 模板中 ScrollViewer 为 `HorizontalSnapPointsType="MandatorySingle"`：一次平移最多移动一项。
- `PivotCurveGenerator::GetDynamicCurveSegments`：轮播标题每移动一个分区，平移量等于离开（向后）
  或进入（向前）的那个标题宽度；`GetStaticCurveSegments`：被裁剪的静态标题按两项的偏移量插值。
- `Pivot_Partial.cpp`：导航按钮只对鼠标/笔显示；WinUI 不用鼠标拖动平移 Pivot。

## macOS 27 触控 API

SDK 中：`NSGestureRecognizer.allowedTouchTypes` 自 macOS 27 默认 `.direct`；
`NSPanGestureRecognizer.minimumNumberOfTouches/maximumNumberOfTouches`；
`NSGestureRecognizer.isCancellableByScrollGesture`；`NSScreen.touchCapabilities`；
`NSView.exclusiveGestureBehavior`；`NSEvent.isTouchSwipeNavigationEnabled`。

## 实现

- 统一的平移状态（`begin/update/endInteractivePan`），三种输入共用：
  - **触摸屏**（macOS 27）：`NSPanGestureRecognizer`，`allowedTouchTypes = .direct`、
    `buttonMask = 0`（鼠标拖动不平移）、单指、`isCancellableByScrollGesture = true`；仅水平方向占优时开始。
  - **触控板**：按 scroll phase 处理，移动 4pt 后判定方向；水平接管，垂直交还外层滚动视图；
    接管后的惯性事件被吞掉，由 Pivot 自己的收尾动画替代。
  - **鼠标滚轮**：无 phase 的水平滚动每次连发只切换一项（200ms）。
- 拖动中内容跟手、相邻项并排出现；最多移动一项；非循环末端用阻尼橡皮筋。
- 轮播标题跟随拖动（向后按当前标题宽度、向前时上一项标题从前沿进入）；静态裁剪标题插值偏移。
- 松手按速度投影 0.25s 判定：超过一半分区则切到相邻项，否则回弹；收尾动画按速度匹配，
  0.15–0.4s 减速曲线。收尾中再次触摸会从当前位置接管。
- 禁用、锁定、项数变化会取消进行中的平移；RTL 物理方向全部镜像。

## 发现并修正的问题

截图审计发现：拖动中直接写标题条 backing layer 的 `transform` 会被 AppKit 重置（单元测试中
未挂到窗口，看不出）。改为平移标题项 frame。另外 `cacheDisplay` 截图不可靠，手势审计改用
`CALayer.render(in:)` 渲染合成后的图层树。

## 验证（`run.sh`，结果在 `results/`）

- `swift test -Xswiftc -warnings-as-errors`：**186 项通过**，新增 `PivotGestureTests` 11 项。
- 质量门禁、[原生验证](results/native-validation.log)、[完整 Gallery 构建](results/xcode-build.log) 通过。
- [手势审计](results/visual.json)：用真实带 phase 的触控板事件驱动，light/dark/RTL × 静态/轮播 ×
  3 个状态共 18 张；断言短拖回弹、仅轮播循环、快速轻扫切换、垂直滑动不接管。人工查看了
  LTR/RTL 轮播拖动中、深色静态橡皮筋截图。

## 局限

- 没有真实触摸屏设备，触摸路径只验证了识别器配置和共用的平移逻辑。
- 惯性投影是对 DirectManipulation 的近似，未与 Windows 对照手感。
- 未区分触摸与鼠标的布局热切换（WinUI 的 InputDeviceType），见后续任务。
