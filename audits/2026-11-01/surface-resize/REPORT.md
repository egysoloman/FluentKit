# 窗口放大时右侧、底部底色滞后

基线为 `ede65a6`。用户录屏为 `录制于 2026-11-01 00.31.23.mp4`（1512×982、120 fps），约 3 秒和 5.5 秒处可见放大后底色追赶窗口边界。本次修复框架的材质布局；未修改、安装或替换正在运行的 Fluent IME。

## 根因与修复

`FluentMaterialView.layout()` 直接设置两个自有 CALayer 的 frame。`NSWindow.performZoom` 触发布局时存在动画事务，AppKit 已经把承载视图和原生背景调整到新尺寸，自有的不透明底色层和 Mica tint 层却又各自启动默认的 bounds/position 动画，短暂露出原生底色。

仅检查 NSView/frame 模型值、使用 `setContentSize` 或截取动画结束后的图像无法发现它。`before/geometry.log` 和 `before/unforced-geometry.log` 都没有显示越界；真正的复现来自 `performZoom` 路径的 presentation layer。

修复在材质层布局时局部禁用隐式动作，使自有背景和玻璃承载视图同步跟随当前 bounds；没有改颜色、材质选择策略或显式主题动画。

## Fluent IME 原路径验证

`SettingsResizeAudit.swift` 编译实际应用的 SettingsWindowController 等源码，使用临时 Rime 数据目录，打开“按键”设置页，调用 `performZoom` 并逐帧记录两个背景层的 model/presentation frame。前后应用源码 SHA-256 完全一致，仅换入修改前后的框架对象文件。

| 检查 | 修复前 | 修复后 |
| --- | ---: | ---: |
| 背景层采样数（16 个状态 × 2 层） | 32 | 32 |
| 仍有 bounds/position 动画的采样 | 6 | 0 |
| presentation 宽度最大落后 | 803.65 pt | 0 pt |

原始数据：`before/zoom/render.log`、`after/settings/render.log`；汇总：`after/geometry-check.json`；两组各 16 张渲染图。前后屏幕可用高度略有差异，因此不声称整张窗口截图逐像素一致，检查的是每一帧背景与其所在视图的同步。

早期 `before/settings/` 是 `setContentSize` 探索，不能作为 zoom 修复证据；该探针当时还依赖 ARC 终止 Rime，退出阶段遇到 C++ 析构问题。最终探针显式终止自身的 Rime 引擎，前后 zoom 验证均正常退出。没有操作用户输入法进程或正式词库。

## 验证范围

- 新回归用例覆盖 mica/nativeMica/acrylic × 材质开关，共 6 组；修复前 24 个断言失败，修复后通过。
- 全量 365 测试、原生 FluentKitValidation、Gallery Debug 构建、Release 质量门禁均通过，未出现 AppKit 约束诊断。
- `ExpanderResizeAudit.swift` 额外记录普通 Expander/SettingsExpander 在浅色和深色下 400→1200→400 pt、展开/收起共 12 个静态状态。两类控件的头部和表面宽度均为窗口宽度减 40 pt。这只证明固定内容的静态宽度正确；用户已明确指出 Gallery 折叠卡，需要继续验证实际嵌套内容及动画，不能据此宣称该项完成。
- 尚未做 Windows 逐像素对拍。本项解决录屏中的瞬时背景滞后，不代替后续搜索框、候选层、页面动画与系统主题通知验收。

## 重现

```sh
swift test --scratch-path /tmp/fluentkit-repair-tests -Xswiftc -warnings-as-errors
swift build --target FluentKit -c release --scratch-path "${TMPDIR}/fluentkit-quality-release" -Xswiftc -warnings-as-errors
./audits/2026-11-01/surface-resize/run-settings.sh /tmp/fluentkit-surface-rerun
./tools/run-quality-checks.sh /tmp/fluentkit-surface-quality
```

应用探针需要现有 Fluent IME 源码、构建后的 FluentIMECore/CRimeBridge 和 librime；路径可通过 `FLUENTIME_SOURCE`、`FLUENTIME_BUILD`、`FLUENTKIT_QUALITY_BUILD` 调整。框架测试与质量门禁不依赖该应用。
