# 实际 Gallery 交互记录

验证对象为本批最终 Xcode 构建的 Gallery，复制到独立临时目录，仅修改应用名称和 bundle ID；二进制哈希及路径见 `gallery-provenance.json`。未修改 Gallery 源码来强行设置焦点，未操作运行中的 Fluent IME。所有界面操作经 CUA。

1. 从 Basic input 目录进入 CheckBox 页面。AX 正文包含 `Remember selection` 复选框，初始为选中；截图也显示实际示例。
2. 用 Tab 从导航按钮进入搜索、Home、All controls，继续经过侧栏各类别及滚动条，最终到达底部 Settings。
3. 此后连续 Tab，AX 持续报告焦点为 Settings，未到达正文复选框。最后一次复验的 AX 返回为：

   ```text
   There has been no change in the accessibility tree for Window: "FluentKit Gallery".
   The focused UI element is 41 button Settings, Value: Not selected, ID: FluentKit.NavigationView.Item
   ```

4. 尝试直接坐标点击示例，CUA 返回 `Accessibility error: AXError.notImplemented`，该路径无法用于验证实际指针聚焦。没有改用外部事件注入。
5. 通过当前隔离应用的 Command-Q 退出，工具确认 `App quit`。

结论：本轮实际 Gallery 键盘焦点视觉验收未完成。已观察到的 Tab 停滞单独列入后续计划，尚未确定是动态页面焦点链、控件键盘处理还是宿主配置；不把猜测记录成根因。96 个独立原生状态与 128 个像素采样验证的是控件/绑定宿主的焦点输出，不能替代这一实际应用路径。
