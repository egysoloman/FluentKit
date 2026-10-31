# 外部 AX 复核记录

工具：CUA，分别启动本批生成的隔离 before/after 应用。以下是观察摘录；没有安装或替换 Fluent IME。

修复前窗口只暴露窗口、Outside release area 文本和窗口按钮，没有 CheckBox。坐标点击/拖动在目标位置返回 `AXError.notImplemented`。另一次非目标位置点击只产生 pressed=false / checked=false 的事件，保留在 before/interactive；不计为 CheckBox 点击成功。

修复后初始查询：

```text
Window: "CheckBox pointer review", App: Fluent CheckBox after.
0 standard window CheckBox pointer review, Secondary Actions: Raise
    1 checkbox Drag out, release; then reenter and release, Value: off
    2 text Outside release area
```

对元素 1 执行点击，新的 AX 状态为 `Value: on`；再次点击为 `Value: off`。隔离窗口的 sendEvent 日志没有记录这两次操作，故它们是 AX 激活证据，不是鼠标事件证据。

坐标拖动及附带 durationMs 的点击仍返回 `AXError.notImplemented`；随后重新读取 AX 状态，没有发生值变化。没有重试成一次不同的成功动作后宣称原拖动成功。应用已通过自己的 Quit 菜单退出。
