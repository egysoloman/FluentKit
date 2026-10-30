# 对后续 Claude 报告的独立核对

核对基于 `7a62d45` 后的当前代码；外部改写已单独保存为 `a73585a`。

## 已修改的三个文件

README 的 1 个 body、SwiftPM Gallery 的 4 个 body、Xcode Gallery ContentDialog 样例的 1 个 body，均只移除了最外层 `FluentAnyView` 包装与多余 return，并改用 `some FluentView`。逐 token 比较确认其他代码不变。`FluentView` 已使用 `@FluentViewBuilder`；单个具体根视图可以返回 opaque type。`FluentAnyView` 的 mount/update 原本只是转发，因此这里没有改变原生视图的所有权、状态存储或更新规则。

验证：README 示例独立 type-check 通过；SwiftPM FluentGallery（warnings-as-errors）通过；完整 Xcode FluentKitGallery Debug 构建通过（本地验证关闭签名）。保留这些示例简化；没有性能基准，不能宣称可感知性能提升。

`.build` 中的扩展属性和构建产物不属于源码差异；无法从 Git 追溯其此前 xattr 状态。本次验证使用独立 scratch/DerivedData 路径，没有依赖这次清理才能通过构建。

## 报告逐项核对

| 项 | 判断 | 后续处理 |
| --- | --- | --- |
| 1 AnyView 样板 | 部分成立。固定根类型的 body 可以简化；辅助函数的异构分支仍可能需要类型擦除，减少文本中的 AnyView 数量不等于移除运行时擦除。 | 6 处已验证并提交；后续逐例检查，不机械替换所有函数签名。 |
| 2 双套命名 | 可用性建议，非已证实缺陷。原生 NSView 控件和绑定/配置描述器的生命周期不同。 | 先解释两层 API；当前不做全库破坏性改名。 |
| 3 必须手工包装原生控件 | 与当前源码不符。`FluentPrimitives.swift` 已让 Button、TextField、Toggle 等实现 FluentUpdatablePrimitiveView。 | 独立 type-check 已验证原生控件可直接放入 builder；文档可以改为展示现有能力。 |
| 4 最多 10 个子视图 | 不成立。`FluentViewBuilder` 已提供 buildPartialBlock，固定 buildBlock 重载不是数量上限。 | 实际编译 14 个 Text 加 3 个原生控件通过。参数包替换的编译收益尚未测量。 |
| 5 缺少预览封装 | 源码中未发现 #Preview / NSViewRepresentable 预览宿主。 | 可增加可选 SwiftUI/Xcode 预览适配，保持框架 macOS 12 基线。 |
| 6 snapshot preconditionFailure | 存在，这是唯一 ID 和已存在 section/item 的编程契约。 | 补明合同及可恢复入口评估；不把失败静默忽略。 |
| 7 强转 | TitleBar 在 `is NSTextField` 短路条件后强转，当前没有越界类型证据；打印处复制系统 NSPrintInfo。 | 可做局部表达式清理，但不应把已检查的类型转换称为已复现崩溃。 |
| 8 URL 无协议白名单 | 行为确实交给系统处理。WinUI HyperlinkButton_Partial.cpp:168 同样将 NavigateUri 交给 Launcher 外部打开。 | 这是导航策略选择，默认只准 HTTPS 会破坏 mailto / 文件 / 应用深链接。评估可选导航策略；当前没有证明具体安全漏洞。 |
| 9 大文件 | 文件规模成立；拆分会缩短增量构建只是推断。 | 可按职责拆分，但须先测量，避免仅为行数制造重构。 |
| 10 未提交改动过多 | 报告已过时。5 个批次已提交；外部示例改写另有单独提交。 | 持续在验证后按改动单元提交。 |
| 11 CI 日期路径 | 路径确实固定。换日期不会自动使保留的旧脚本失效，但 CI 与审计档案耦合。 | 建立固定质量检查入口；避免自动挑“最新日期”导致门禁随临时报告漂移。 |
| 12 目录状态 | FlipView 确实有源码但仍落入 missing；CreateMultipleWindows 当前已是 partial，不能笼统说仍缺失。 | 修正 FlipView 并添加对应样例。类型存在只能证明存在，不能自动证明 implemented / 状态覆盖完成。 |
| 13 ROADMAP 过长 | 文档结构建议。 | 分离当前能力、未完成验收与历史变更，保持原验收范围。 |
| 14 构建优化收益 | 未提供对照测量，原因归属未证实。 | 区分 clean/incremental、Debug/Release 与 target，再评估文件拆分或 builder 改写。 |

## 功能优先级

继续以 WinUI 源码和可复现差异推进，而不按控件类型存在就宣称还原完成。当前先修复集合视口变化导致的行宽错配、滚动位置跳变及窄窗口约束问题；随后处理目录/质量门禁和文档入口。CalendarView、集合选择/模板、命令控件状态、缺失控件、真实 Windows 对拍、中文输入法及 VoiceOver 保留在整体目标中。

对照：`microsoft-ui-xaml-winui3-release-2.3.1/src/dxaml/xcp/dxaml/lib/HyperlinkButton_Partial.cpp`；本项目 `Sources/FluentKit/FluentDeclarativeCore.swift`、`FluentPrimitives.swift`、`FluentCollectionSnapshot.swift`、`FluentTitleBar.swift`、`FluentPrinting.swift`、`FluentHyperlinkButton.swift` 与 GalleryCatalog。

## 后续落实（2026-10-31）

CI 已改用固定的 `tools/run-quality-checks.sh`，保留日期目录中的历史脚本和数据；验证见
[quality-entry/RESULTS.md](quality-entry/RESULTS.md)。FlipView 目录和样例已更新，并独立复现、修复
五个绑定/选中项/过渡问题，见[后续证据](../2026-10-31/flip-view/RESULTS.md)。其覆盖仍为 partial。
