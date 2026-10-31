# MapControl 实现（2026-10-31）

Gallery 目录中 MapControl 原为 **missing**，现新增公开 `FluentMapControl`，覆盖记为 **partial**。

## WinUI 参照

`src/controls/dev/MapControl/MapControl.idl` 与实现：WinUI 3 的 MapControl 通过 WebView2 加载 Azure Maps
（`map.html`），公开 `Center`、`ZoomLevel`、`Layers`（`MapElementsLayer` 中的 `MapIcon`）、
`InteractiveControlsVisible`、`MapElementClick`、`MapServiceToken`、`MapServiceErrorOccurred`。

## 实现

- macOS 上以 MapKit 作为后端（不需要服务令牌）。API 对应：`center`/`zoomLevel` 双向绑定、
  `icons`（`FluentMapIcon`，按 id 同步，未变化的保留原注释对象）、`interactiveControlsVisible`
  （缩放按钮、指南针、比例尺）、`onMapElementClick`。
- 缩放级别使用与 Azure Maps 相同的 Web Mercator 尺度（0 级 = 256pt 显示全球），与 MapKit 跨度互相换算。
- 触控板、鼠标、触摸手势由 MapKit 自身处理；用户平移缩放写回绑定。
- Gallery 工程开启沙盒出站网络（`ENABLE_OUTGOING_NETWORK_CONNECTIONS`），否则地图瓦片无法加载。

## 验证（结果在 `results/`）

- `swift test -Xswiftc -warnings-as-errors`：**232 项通过**，新增 `MapControlTests` 3 项。
- 质量门禁、Gallery 挂载检查、原生验证、完整 Gallery 构建通过。
- 未做截图审计：地图瓦片依赖网络且异步加载，截图无法稳定反映控件状态。

## 局限

- 只支持图标层；没有折线、多边形等其他 MapElement，也没有 `MapServiceErrorOccurred`。
- 视觉是 Apple 地图而非 Azure Maps。
