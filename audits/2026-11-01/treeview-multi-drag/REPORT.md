# TreeView：批量子树移动与原生点击路径

基线：`74cbf42`。框架新增 `onMoveItems`，原 `onMove` 保持单行兼容行为；TreeView 仍为 Partial。

## WinUI 参照与实现

对照固定版本 [TreeViewList.cpp](https://github.com/microsoft/microsoft-ui-xaml/blob/winui3/release/2.3.1/src/controls/dev/TreeView/TreeViewList.cpp) 的 `OnDragItemsStarting`、`GetRootsOfSelectedSubtrees`、`GetRootOfSelection` 和 `OnDrop`，以及同目录 `TreeViewItem.xaml` 的计数覆盖层。仓库内参照文件哈希保存在 `before/source-sha256.txt`。

WinUI 在多选且存在已选节点时移动已选子树；通过祖先归并避免把父节点及其子节点重复移动。新接口采用这一语义，一次报告 `ids / parentID / index`，应用先移除所有根，再按给定顺序插入。勾选顺序保留，初始无序 Set 使用树顺序。拖动图像加入选中节点计数，20pt 高、白色边框与 Caption 文本。现有单条目处理器不被静默改成多次回调，最后设置的移动处理器生效。

当前拖动成员在会话开始时冻结，但会读取当时最新绑定值；应用更新替换了处理器时使用新闭包。落点校验与接受共用移动计算，拒绝自身/后代、未知父级、越界索引、原地移动和其他树的拖动源。结构更新会让旧落点校验失效；延迟加载可以继续当前拖动，但须重新校验。回调前清除会话，防止重入重复调用。

## 独立发现

1. **旧单条目计算缺少最终防护**：修复前，计算函数对循环父级、未知父级和非法索引给出有效结果，5 个断言失败。旧 UI 的 validateDrop 已检查常见循环，因此不能把计算缺陷夸大为所有普通鼠标路径都能制造循环。证据：`before/validation-test.log`。
2. **绘制的复选框收不到真实点击**：CUA 点击 Notes 复选框只选择/调用行，Checked 仍为 1；Space 才变为 2，见 `before/pointer-interactive/states.json`。原因是 NSOutlineView 接管鼠标事件，普通 NSView cell 的 mouseDown 未得到执行。现由原生 outline 转发附件命中，其他区域仍走 AppKit。修后同坐标直接点击变为 Checked: 2，点击 Specs 箭头正常展开且不调用行。LTR/RTL 回归同时检查绑定与展开集合。
3. **Gallery 延迟加载丢失已移入节点**：旧 `Entry.load` 替换 children，Plan/Notes 移入未加载 Remote 后，展开时消失。改为追加加载结果。`before/lazy-load.json` 由旧源文件仅放宽 Entry 可见性后编译得到，`movedEntriesPreserved=false`；修后为 true。两份 `GalleryLoadSource.swift` 注明了唯一审计用可见性变化，逻辑来自各自源文件。

Gallery 以一个状态更新应用整个批次；失败的移除/插入不会提交半成品。新增说明曾把独立窗口从 600pt 撑至 653pt，已缩短文案；最终 12 个动态状态均保持 600pt。

## 验证证据

- 9 项新增回归：批量索引与顺序、选择子树归并、旧 API、状态冻结/最新回调、移除节点、延迟加载、原生落点校验、鼠标附件命中。最终全量 **401 项，0 失败**。
- 原生 Gallery 的批量应用、未加载目标、加载后保留、顺序、失败事务：light/dark/RTL 共 **12 个状态**，见 `after/move-gallery/`。这里直接调用与 Gallery 回调相同的数据应用方法，**不是物理拖放验收**。
- 原 Gallery 的选择、展开、延迟加载、单选状态：另 **15 个状态**，见 `after/gallery-final/`。
- 实际 CUA 点击证据在 `after/interaction-trace/`。原生会话生成的拖动图像已输出为 `drag-preview.png`，确有计数 2；与事件/组件坐标一并保留。
- 全量测试、原生验证、Release 门禁、Gallery 构建日志使用 `after/` 中的 final/pointer 文件；第一次 400 项结果在加入点击修复之前，不替代 401 项结果。

初始批量测试还发现立即修改选择绑定后开启拖动会读取旧集合，现于开始会话时同步取最新值。相关失败在 `after/tests-initial.log`；临时编译错误日志保留，未计入运行时缺陷。

## 尚未关闭

原生拖放落地尚未通过实机验收。本次 CUA 记录有会话建立/计数图像，但结束操作为 0，未收到目标 validate/accept；记录中鼠标释放早于会话建立。标准应用启动也复现这一时序，`after/launch-services/drag-events.json` 确认 source pasteboard 与目标注册类型一致，本地操作掩码为 16（move）。不能把模型回调测试或图片等同于拖放成功，也没有据此改写 AppKit 的拖动跟踪。需继续区分自动化事件时序和实际系统拖动行为。

跨树传输、展开动画、完整拖动视觉状态及取消行为、Windows 对拍、真实触摸和 VoiceOver 保持开放。绘制附件当前沿用已有按下触发策略；复选框完整按下/移出/释放状态与 chevron 完整 padding 命中仍需继续对照 WinUI。此前实际 IMK 候选定位也未被本批关闭。

## 重跑

```sh
swift test --scratch-path /tmp/fluentkit-repair-tests -Xswiftc -warnings-as-errors
zsh tools/run-quality-checks.sh /tmp/fluentkit-tree-drag-quality
zsh audits/2026-11-01/treeview-multi-drag/run-gallery.sh /tmp/fluentkit-tree-moves
zsh audits/2026-11-01/treeview-multi-drag/run-load-comparison.sh
zsh audits/2026-11-01/treeview-multi-drag/build-interactive.sh
python3 audits/2026-11-01/treeview-multi-drag/check_results.py
```

`build-interactive.sh` 仅构建独立审查应用，需用 CUA 或人工操作；不会安装或替换用户应用。`check_results.py` 检查本次保留的证据，不会把未完成的拖放标为通过。
