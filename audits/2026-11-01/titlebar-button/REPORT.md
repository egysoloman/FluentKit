# TitleBar 返回按钮逻辑与动画

基线 `497edab`，macOS 27.2 / Swift 6.4。用户截图的按钮来自 Fluent IME 的 `FluentTitleBar`。
应用的 `onBack` 明确调用 `navigate(.home)`，即返回拼音主页；它没有历史栈。本批保持应用导航目的地，修复框架按钮的输入状态。

## 独立确认

- 基线三项逻辑回归产生 **6 处失败**：空格按下立即导航且自动重复，Return 重复导航，祖先隐藏后 AX 仍能调用。
- 基线 Release 探针中 **8/8** 组合隐藏再显示后仍保留旧悬停背景；normal/redisplayed 图片像素均不同。
- 原 mouseDown 进入 AppKit 阻塞追踪后，按原始按下位置重算 hover；它不能正确表达移出、移回和释放位置。
- 原箭头为静态路径，缺少 AnimatedBack 的按压收短和释放回弹。
- 40pt 宽度、2pt 外边距、32/48pt 标题栏高度与 WinUI 参考一致；截图里的大灰底在持续悬停时是正常状态，不能全部归为触屏尺寸问题。

## 修复

按钮独立到 `FluentTitleBarButton.swift`，保持公开 API。鼠标按下只捕获；释放在内才触发，拖出取消、移回恢复。
Space 在松开时调用一次，Return 忽略重复；Escape、失焦、禁用、隐藏、窗口失活取消挂起的状态。
程序调用和 AX 检查整个祖先可见性。按压不会缩放整个按钮和命中区域。

按 WinUI 的 48-unit AnimatedBack 以 16pt 显示的关键值：箭头前端内收 3pt，尾端移动约 0.313pt；
150ms 按压，约 317ms 释放，释放经过轻微反向过冲。RTL/Forward 镜像，Reduce Motion 立即到端点。
本地圆角描线路径与中断时的回弹强度为 macOS 实现，没有逐像素复刻整个 Lottie 资产或其排队算法。
失活前景改为对应的 tertiary 色阶。顺手移除 TitleBar hitTest 中已有类型检查后的重复强转。

参考：
[TitleBar 模板](https://github.com/microsoft/microsoft-ui-xaml/blob/winui3/release/2.3.1/src/controls/dev/TitleBar/TitleBar_themeresources.xaml)；
[AnimatedBackVisualSource](https://github.com/microsoft/microsoft-ui-xaml/blob/winui3/release/2.3.1/src/controls/dev/AnimatedIcon/AnimatedVisuals/AnimatedBackVisualSource.cpp)。
本地相同版本在仓库忽略目录 `microsoft-ui-xaml-winui3-release-2.3.1`；仅参照状态、尺寸和关键帧，未移植生成实现。

## 验证

- 新增 11 项逻辑/状态/真实定时器回归；全量 **364 tests, 0 failures**。
- Xcode Gallery BUILD SUCCEEDED。
- 原生验证 PASS、Release 质量门禁通过，日志保留在 `after/`。
- 32 个 Release 渲染状态通过几何和回调检查；修复后 **8/8** 隐藏再显示图片与正常态完整 RGBA 像素一致。
  人工检查深色按压和恢复截图。基线与修复后使用同一公开 API 探针。
- 实际动画定时器回归检查按压端点、释放终点和隐藏后取消；减少动态效果下测试立即抵达正确端点。

复跑：`./audits/2026-11-01/titlebar-button/run.sh /tmp/titlebar-button-new`。
结果检查：`python3 audits/2026-11-01/titlebar-button/check_results.py /tmp/titlebar-button-new`。
公开 API 探针覆盖 Light/Dark × LTR/RTL × 32/48pt，normal、hover、pressed、隐藏再显示，共 32 张原生 layer-tree 图。
旧库 SHA256 与上批 Release 构建一致；原始日志与图片保持在 before/。
真实 VoiceOver、物理触屏和 Windows 截图对拍未验收。本批未安装或替换运行中的输入法。
