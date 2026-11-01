# Tooltip 局部录屏

`tooltip-follow.mp4`：580×240，约 9.31 秒，H.264，无音频。ScreenCaptureKit 对独立演示进程的窗口及子浮层做实际桌面合成录制，仅保留标题栏右侧 290×120pt。源显示器 2×，没有录制其他应用或桌面内容。

录制使用已通过门禁的 Release FluentKit（`b2cec0c` 运行时代码），未包含进行中的通用材质修改。由窗口自身依次调用按钮/Tooltip 的悬停入口，演示最小化→最大化→关闭、多次返回和 80ms 中断；不是物理鼠标悬停验收。`preview.png` 是视频 2.4 秒帧。

工具：`TooltipRecording.swift`。ScreenCaptureKit 使用 `SCShareableContent.currentProcess` 与限定当前应用的 filter，包含子窗口，不请求其他应用的屏幕访问。`SCStreamConfiguration.backgroundColor` 为 assign 属性，源码明确维持 CGColor 生命周期；第一版临时颜色被释放导致录制前崩溃，修正后完整录制成功。录制不修改框架或 IME 运行实例。

视频证明桌面合成中的 Tooltip 阴影和连续过渡可见；真实鼠标、高刷帧时、多显示器和缩放变化另行验收。
