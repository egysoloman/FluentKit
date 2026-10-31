# TreeView 打磨（2026-10-31）

对照 WinUI `TreeViewItem.xaml`、`TreeView_themeresources.xaml`、`TreeViewItem.cpp`、`ViewModel.cpp`。

- 行模板：行高 32（MinHeight 28 + Margin 4,2），圆角 4，SubtleFill 悬停/选中填充，3x16 强调色选中指示条；
  每级缩进 16，chevron 列 Padding 14,0（多选时 0,0,14,0），无子节点时保留空位；不再用 NSOutlineView 原生三角和缩进。
- `FluentTreeViewSelection`：`.none` / `.single` / `.multiple`。多选使用三态复选框（勾选父节点会勾选整棵子树，父节点状态由子节点推导，外部写入的集合会被规范化）。
- `.expandedIDs`（双向绑定）、`.onExpanding`（加载 `hasUnrealizedChildren`）、`.onCollapsed`、`.onItemInvoked`、`.onMove`（拖拽重排，报告“移除后的索引”）。
- 键盘按 HandleExpandCollapse：左键折叠或跳到父节点，右键展开或跳到首个子节点（RTL 方向镜像）；多选时空格切换勾选，Return 触发 ItemInvoked。
- 新增 `FluentTreeView` / `FluentTreeViewNode` 类型别名，原有 `FluentOutline` API 保持兼容。

验证：TreeViewPolishTests 5 项；全量 254 项测试通过；FluentKitValidation PASS。
未做：Gallery 的 TreeView 示例，多项拖拽，展开动画。
