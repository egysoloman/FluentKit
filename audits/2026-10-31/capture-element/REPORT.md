# Capture Element / Camera Preview 实现（2026-10-31）

Gallery 目录中该条目原为 **missing**，现新增公开 `FluentCaptureElement` 与 `FluentCameraCapture`，覆盖记为 **partial**。

## 参照

WinUI Gallery 的 “Capture Element / Camera Preview” 示例使用 `MediaCapture` 与 `MediaPlayerElement`
预览摄像头。WinUI 本身没有独立的 CaptureElement 控件实现可对照，这里按 Gallery 示例的行为实现。

## 实现

- `FluentCameraCapture`：权限查询与请求、设备列表、按设备 id（或默认）启动/停止 `AVCaptureSession`，
  未授权、无摄像头、无法添加输入时抛出明确错误；会话在后台线程启动。
- `FluentCaptureElement`：`AVCaptureVideoPreviewLayer` 预览，Uniform / UniformToFill / Fill，
  默认镜像（前置摄像头习惯），无会话时显示占位内容；同一会话复用预览层。
- Gallery 工程开启 `ENABLE_RESOURCE_ACCESS_CAMERA` 并加入 `NSCameraUsageDescription`
  （已确认生成的 Info.plist 中包含该键）。

## 同批修复

`FluentVStack`/`FluentHStack` 只有一个子视图时无法通过类型检查（今天第三次绊住示例）。新增
`@_disfavoredOverload` 的泛型重载包装单一子视图，现有调用仍解析到原函数；新增 `SingleChildStackTests`。

## 验证（结果在 `results/`）

- `swift test -Xswiftc -warnings-as-errors`：**235 项通过**，新增 `CaptureElementTests` 2 项、`SingleChildStackTests` 1 项。
- 质量门禁、Gallery 挂载检查、原生验证、完整 Gallery 构建通过。
- 未做实机摄像头截图：需要用户授权，自动化环境中不能弹出系统权限对话框。

## 局限

- 没有拍照/录像、分辨率与帧率选择；只做预览。
