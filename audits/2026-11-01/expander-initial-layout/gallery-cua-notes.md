# 实际 Gallery 操作记录（2026-11-01）

使用 CUA 操作 `/tmp/fluentkit-gallery-review/Build/Products/Debug/FluentKitGallery.app`。
退出旧进程后 UI 回到 Home；在最新构建中搜索 Expander 并打开结果。

1. 初始 Interactive sample / More details / Open upward 的 AX 状态均 Expanded；截图中正文、上下方向标题和 Source identity 卡片无交叠。
2. 点击 More details：AX 变为 Collapsed，正文移除，下方 Open upward 与 Source identity 同步上移，截图未保留旧正文空白。
3. 点击外层 Interactive sample：AX 变为 Collapsed，两个内层项目退出可访问树。
4. 再打开外层：More details 仍为 Collapsed，Open upward 仍为 Expanded。截图显示外层背景包住内容，后续卡片位置正确。

此记录是实际应用的到达状态检查；不替代逐帧、高刷时序或 Windows 对拍。
`gallery-final/images/` 是使用同一 Gallery 页面源码的独立驱动图像，不是上述 CUA 截图。
