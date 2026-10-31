# TreeView 展开事件：查询、真实变化与恢复

基线：`d60edee`。本批修复三项独立的事件语义问题。框架仍未完成完整 VoiceOver 或 WinUI 行为验收。

## 复现与修复

1. **查询触发加载**：原 `shouldExpandItem` 调用 `onExpanding`。AppKit 在辅助功能客户端读取 `AXDisclosing` 是否可写时也调用该资格查询。测试连续查询三次，旧代码加载三次，节点仍折叠；实际 Gallery 仅被 CUA 读取，Remote 就变成 `Expanded remote`。现资格查询只返回可用性，加载事件改到 [AppKit 实际即将展开通知](https://developer.apple.com/documentation/appkit/nsoutlineviewdelegate/outlineviewitemwillexpand%28_%3A%29) 中。
2. **绑定变化没有事件**：原实现用同一个标志同时禁止绑定回写和事件，导致修改 `expandedIDs` 不能调用按需加载。现在把初始/重建恢复与真实绑定变化分开：挂载后的实际展开/折叠会发出事件，相同值、初始快照、加载子项后的重建恢复不会重复触发。
3. **折叠回调重开被覆盖**：原 `onCollapsed` 看到的绑定仍含刚折叠节点，在回调里要求重开会被随后写入的旧折叠结果覆盖。现先发布折叠状态，再调用回调，保留应用随后提出的新状态。

固定对照 [WinUI ViewModel.cpp](https://github.com/microsoft/microsoft-ui-xaml/blob/winui3/release/2.3.1/src/controls/dev/TreeView/ViewModel.cpp) 的 `TreeViewNodeIsExpandedPropertyChanged` 及 [TreeView.cpp](https://github.com/microsoft/microsoft-ui-xaml/blob/winui3/release/2.3.1/src/controls/dev/TreeView/TreeView.cpp) 的节点展开/折叠事件转发。WinUI 的属性变化会发出事件，不依赖鼠标入口。文件哈希见 `before/source-sha256.txt`。

**行为变化**：挂载后修改 `expandedIDs` 现在会触发 `onExpanding` / `onCollapsed`。过去依赖“程序改变状态不发事件”的应用需要按实际状态转换处理；此变化已写入 API 文档、README 和 CHANGELOG。初始快照和内部重建仍静默，避免重复加载。

## 验证

- 三项最终回归在隔离的 `d60edee` 工作树运行，**13 处失败**，无 unexpected failure。它使用与修后相同的测试文件；基线提交和测试文件/哈希保存在 `before/`，临时工作树已移除。
- 修后全量 **407 项测试，0 失败**。覆盖真实 AppKit AX 资格读取、原生展开、绑定改变、初始/重建恢复、折叠回调内重开，并保留原有键盘、点击、批量移动等回归。
- 实际 Gallery 的 CUA 对照见 `before/interactive/` 与 `after/interactive/`。旧 Release：只读取即出现 `Expanded remote`。修后 Debug：读取后仍显示 `Open Remote to load its children.`；执行辅助功能 Expand 才显示两个远程子项，再执行 Collapse 正常折叠。首次 Expand 工具返回元素失效，但随后读取明确看到操作已成功；未按报错重复展开。
- 原生验证、Release 门禁、Gallery 构建通过；实际 Gallery 15 个选择/展开状态及 12 个加载/重排状态通过。原始日志在 `after/`。

## 证据边界与探针修正

AppKit 当前返回的 outline AX 行代理使用旧的公开非正式协议，SDK 的 Swift typed-array 桥接会因协议不匹配失败；直接调用现代行选择器也不支持。最终测试使用公开的 `accessibilityRows`、`accessibilityIsAttributeSettable:` 和 `accessibilityAttributeValue:`，以 `AXDisclosing` 读取实际代理，无私有 API 或函数指针强转。

早期探针对代理直接写属性没有触发真实外部 AX 动作，相关初始日志保留，但不作为框架缺陷数。最终单测分别验证查询与原生展开；外部辅助功能 Expand/Collapse 由 CUA 对实际 Gallery 验证。没有把修正探针后消失的失败记成产品修复。

本批未改已安装输入法。完整 VoiceOver 导航、真实输入设备、原生数据拖放落地、跨树传输、展开动画、共享 CheckBox 精细外观与真实 IMK 候选定位仍开放。

## 重跑

```sh
swift test --scratch-path /tmp/fluentkit-repair-tests -Xswiftc -warnings-as-errors
zsh tools/run-quality-checks.sh /tmp/tree-expansion-quality
zsh audits/2026-10-31/treeview-lifecycle/run.sh /tmp/tree-expansion-gallery
zsh audits/2026-11-01/treeview-multi-drag/run-gallery.sh /tmp/tree-expansion-moves
zsh audits/2026-11-01/treeview-expansion/build-review.sh after
python3 audits/2026-11-01/treeview-expansion/check_results.py
```

`build-review.sh` 使用已有 Release 产品；也可用 `FLUENTKIT_EXPANSION_PRODUCTS` 明确指定 Debug 产品。它创建独立验证应用，各阶段输出互不覆盖。
