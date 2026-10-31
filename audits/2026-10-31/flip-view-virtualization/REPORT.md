# FlipView 虚拟化与交互复核

基线：`02a2556`。环境：macOS 27.2 / Swift 6.4（Swift 5 模式）。本目录保留修复前原始数据；不改写历史审计。

## 独立复现

旧实现对 1,000 项立即创建全部页面，每次父更新又执行全部 builder；追加一项会替换现有页。
绑定 setter 拒绝写入时，画面与事件却仍切到请求页。`before/tests.log` 中三个回归用例共七处断言失败；
可与 `baseline-tests.swift`、`before/performance.json` 核对。

## 修复及源代码依据

- `FluentFlipView` 延迟评估内容；默认位置 ID 无需扫描全部内容。新增显式 `id:` 保持当前项和挂载原生页身份；显式 ID 元数据更新仍为 O(n)，未宣称整次更新 O(1)。重复 ID 按出现序号区分，不保证重复项移动的身份语义。
- 缓存当前页及相邻页，空闲最多三页；远跳动画额外保留一个出场页。缓存外页面释放，持久状态应放模型。
- 绑定写入后重新读取接受值；同步修改数据/绑定、拒绝/重定向、延迟观察通知均以当前状态为准。稳定 ID 前插不丢编辑器焦点；移除当前页会移交焦点。
- 新增垂直方向；指针按钮分别为 16×38 / 38×16、边距 1，方向键与 RTL 对应。保留传统滚轮 200ms 连续事件抑制及反向立即响应。
- 分阶段滚动显示当前/邻页位移，释放最多一页；父刷新不重置拖动。真实渲染发现宿主拥有的 layer transform 会被布局清除，已改用页面 frame 位移并验证像素保持。
- 拖动停住后释放不再沿用过期速度；共享输入层同时覆盖 Pivot 回归。禁用祖先中新创建的懒页继承禁用状态，恢复后保留子项原有禁用状态。

参照本地 WinUI 3 release-2.3.1：
`src/controls/dev/CommonStyles/FlipView_themeresources.xaml` 的 VirtualizingStackPanel、MandatorySingle、两轴按钮尺寸；
`src/dxaml/xcp/dxaml/lib/FlipView_Partial.cpp` 的方向与滚轮抑制路径。
当前手势投影/回弹是 macOS 适配，不声称复刻 DirectManipulation 物理。

## Release 数据

同一公开 API 探针、1,000 个文本页面，处理包含更新和布局；不是物理输入延迟。单次环境样本，不能外推整个框架。

| 场景 | 修复前 | 修复后 |
| --- | ---: | ---: |
| 首次 builder / 原生页 | 1,000 / 1,000 | 2 / 2 |
| 30 次父刷新 builder / 原生更新 | 30,000 / 30,000 | 60 / 60 |
| 父刷新平均处理 | 50.797 ms | 0.484 ms |
| 首次处理 | 201.171 ms | 30.712 ms |
| 末页后追加一项，新建页数 | 1,001 | 1 |
| 追加处理 | 184.803 ms | 1.176 ms |

原始数据：`before/performance.json`、`after/PerformanceAudit.json`；各自记录构建产物 SHA256。

## 验证

- 全量 **341 tests, 0 failures**；原生验证、Xcode Gallery、Release 质量门禁全部通过。日志在 `after/`。
- 新增 12 个 FlipView 回归、1 个共享输入回归；旧用例去掉“所有隐藏页永远挂载”的假设。
- 56 个真实 layer-tree 渲染状态：Light/Dark × LTR/RTL × 水平/垂直，覆盖初始、25% 拖动、30 次父刷新、回弹、下一页、稳定 ID 前插、末页。
- 几何和选择断言全部通过；8 对 partial/refresh PNG 完整 RGBA 像素一致。查看 `after/contact-sheet.png` 及 `after/images/`；抽查水平裁剪、垂直位移、导航按钮与深浅色状态。
- 手势事件直接发送给 FlipView 和共享 driver，没有向 NSScrollView 注入合成滚动。

复跑：`./audits/2026-10-31/flip-view-virtualization/run.sh /tmp/flip-view-audit-new`。
请使用新输出目录；保留已提交的证据不变。

## 未完成的对齐

同轴 phased 手势在首尾仍为弹性返回，WinUI 开启滚动链；跨轴及传统边界滚轮已转发。完整 item-container 语义、按钮 glyph/material/按压比例、精确物理仍待对齐。
物理触屏、真实 VoiceOver 和 Windows 像素对拍未验收。本批不将 FlipView 标为完整实现。
