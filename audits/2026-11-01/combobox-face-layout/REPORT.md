# ComboBox 面板高度与文字裁切

本批从实际 Gallery 的 SystemBackdrops 示例独立复现。基线为 `aad6d45`，此前的材质实现已提交。本批代码提交为 `d2df122`。运行中的 Fluent IME 未安装、替换或停止。

## 根因和修复

宿主声明 32pt intrinsic height，但填满宿主的原生 NSComboBox 同时提供 23pt 高度、750 的 hugging priority。原生编辑文本框也提供自己的尺寸和左右 2pt 对齐边距。结果不是某个 frame/Expander 独有：直接挂载、frame、VStack、Expander 和实际 Gallery 示例都把宿主压到 23pt。

- 内部 data/accessibility bridge 和 editable field 不再提供独立 intrinsic metrics，布局尺寸由 Fluent 宿主决定。
- 可编辑字段的 alignment rect 与面板重合，编辑器不再横向溢出 2pt。
- 宿主高度取主题最小高度和完整字体行高加 5/7pt padding 的较大值。默认仍为 32pt；大字体可增长，compact/small 也优先保留完整文字。显式 `.frame(height:)` 仍可覆盖。
- 未给 Gallery 示例添加强制高度。

本轮核对 [WinUI ComboBox 模板](https://github.com/microsoft/microsoft-ui-xaml/blob/main/controls/dev/ComboBox/ComboBox_themeresources.xaml)：`ComboBoxMinHeight` 为 32，属于最小高度而非固定高度。Fluent 的主题密度和字号覆盖仍是本项目扩展，不据此声称 Windows 逐像素一致。

## 证据

`ComboBoxGeometryAudit.swift` 在自己的原生窗口中挂载真实控件，输出 frame/intrinsic/fitting size 和内部优先级，不依赖新增单元测试的判断。

| 场景 | 修复前 | 修复后 |
| --- | ---: | ---: |
| 选择式：直接 / frame / stack / Expander | 全部 23pt | 全部 32pt |
| 可编辑：直接 / frame / stack / Expander | 全部 23pt | 全部 32pt |
| 实际 MaterialGallerySample | 23pt | 32pt |

9 个状态见 `before/geometry.json` 和 `after/geometry.json`。两个条件（高度与编辑器边界）共 18 项失败归零，见 `comparison.json`。对应 PNG 用 AppKit cacheDisplay，仅检查面板文字与几何，不作为透明材质合成证据。修复前的可编辑字段为 `x=-2, width=host+4`，修复后准确填满面板。

实际重新启动构建后的 Gallery，通过 CUA 搜索 SystemBackdrops，检查 Preset，再打开列表选择 Liquid Glass；两种标签均完整显示，值正确更新。`gallery-after.png` 和 `gallery-after-ax.txt` 保存实际窗口结果，非自有 fixture 替代。

新增 4 项回归检查：两种模式×四种容器、三种密度×1/1.5/2 字号实时更新、controlSize/显式尺寸、活跃原生编辑器与 marked text 保留。初版测试把 small 的 26pt 当固定值而失败；按最小高度契约修正为同时检查最小值和完整文本行，保留原始日志。

## 验收与剩余范围

- 定向测试：4 项、0 失败（`targeted-tests.log`）。
- Gallery Debug 构建通过（`gallery-build.log`）。
- 完整 XCTest：476 项、0 失败（`full-tests.log`）；原生验证 PASS（`native-validation.log`）；Release 门禁通过（`quality-run.log` / `quality/`）。初始化约束警告仍明确保留如下。
- 对修复前 `aad6d45` 的独立源码副本运行同一容器回归，8 个场景产生 16 项高度/编辑器边界失败；新实现归零。该副本同样在 `FluentDisclosure.swift:342` 报告 Expander 初始化约束冲突，确认是既有问题，另行保留在队列第 26 项。本批未修改 Expander，也不据测试通过宣称告警消除。见 `baseline-test.log`。
- Toggle 在实际 AX 树缺失仍是独立任务；真实中文候选、VoiceOver、多显示器/缩放、Windows 对拍继续保留。
