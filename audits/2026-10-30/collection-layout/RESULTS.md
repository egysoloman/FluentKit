# CollectionView 视口尺寸交接修复

## 结论

本机原复现中的行宽和极窄视口约束警告已消除，同时修复了缩放导致的滚动位置跳变。新增回归在修改前的 `7a62d45` 上出现 9 个断言失败：滚动到第 4,000 项后缩放，offset 从约 127,994 跳到 2,002。修复后，legacy/overlay 滚动条和 40–1,200 点宽度切换均保持滚动位置、单列和虚拟化。

这是针对已经复现的布局时序问题的关闭，不是跨所有 macOS 版本、全部 WinUI 控件和辅助技术的验收结论。

## 源码依据

- WinUI `src/dxaml/xcp/components/moco/lib/StackingLayoutStrategyImpl.cpp:41`：非虚拟化方向使用当前窗口约束，扣除 padding 后的 measure size 下限为 0；对应 arrange 分支在约第 138–147 行也对不足的空间作零值限制。
- WinUI `src/controls/dev/Repeater/StackLayout.cpp:62`：将当前 availableSize 交给 FlowLayoutAlgorithm，并明确关闭 wrapping。这里作为单列堆叠和尺寸输入时序的参照，不声称把整个 WinUI 布局算法移植到了 AppKit。
- 本项目 `Sources/FluentKit/FluentCollection.swift`：原来等 NSScrollView.layout 执行后才计算行宽，documentView 宽度约束也在后续 Auto Layout 中交付。NSCollectionView 在原生 resize 内已经开始排列项目，因此会读到旧行宽。

诊断轨迹保存在 [timing-trace.log](timing-trace.log)。滚动条使视口 300 → 283 点时，项目仍是 296 点；窄窗再扩宽时，旧窄项目被短暂排成多列，集合高度骤减，滚动位置被截断。仅在 flow layout.prepare 里改 itemSize 已经太晚，[该实验](prepare-only-experiment.log)保留在案，诊断代码未进入运行时。

## 修复

1. 通过 clip view 的同步 autoresizing 交付 document width；在原生 setFrameSize/setBoundsSize 改宽之前计算行和 header metrics。
2. 改宽后再次使 native layout 失效，避免从零宽恢复时复用已缓存的旧 extent。
3. 完全折叠时保留一个不可见的有效布局槽；极小的正宽度仍使用实际可用宽度和可容纳的横向 inset，不申请负宽度，也不让像素对齐把正尺寸舍入成零。
4. 项目内容要求非负宽高；空间不足时 trailing/bottom padding 以较低约束优先级让步。正常宽度的 16/12 点 list padding 保持原契约。
5. Release gate 对 CollectionAudit 日志中的 invalid flow-layout / conflicting-constraint 信息直接失败。它不会静音日志，也不把测试断言通过替代日志检查。

## 验证

- [resize-before.log](resize-before.log)：同一新增缩放测试在修改前源码上失败；独立临时目录构建，没有覆盖工作区。
- [tests-after.log](tests-after.log)：135 项测试通过，包含 19 项审计回归；无编译警告、对应布局警告或约束冲突。
- [validation-after.log](validation-after.log)：FluentKitValidation: PASS。
- [repaired/CollectionAudit.json](repaired/CollectionAudit.json)：1,000/5,000 项、普通宿主/WindowShell 四种场景，每 10 次输入共更新 180 个可见行实例，rowMakes 和 nativeAttachments 均为 0；[CollectionAudit.log](repaired/CollectionAudit.log)为空。
- 窄宽切换检查同时覆盖可见行数量、5,000 项的稳定总高度、第 4,000 项附近的滚动 offset，以及小于 80 个累计 content mount 的约束。
- 单独检查带 header 的网格在 LTR/RTL 下适配宽度。NSTextField 使用 alignment rect 检查内容槽，避免把 AppKit 自带的 frame 边距误判为越界。
- 无窗口宿主从 300 → 0 → 0.5 → 2 → 160 → 0 → 600 点恢复后仍维持单列正确 extent。
- [pixel-comparison.json](pixel-comparison.json)：现有浅/深状态基线零差异；此项仅证明这些受控截图未受影响。
- [gate-regression.json](gate-regression.json)：新 gate 会拒绝上一版保留下来的真实布局警告，防止仅有通过案例。
- [verification.json](verification.json) 记录源码 hash、验证状态及保留的未完成项目。

原 `repaired/` 下的初轮数据保持历史含义；此目录中的 `repaired/` 是后续修复的独立运行结果。其他目标，包括完整 Mica 合成、真实 Windows 对拍、中文候选窗、VoiceOver 和尚未实现的控件，继续保留。
