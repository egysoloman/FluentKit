# 通用可选材质与独立复验

用户要求保留预置默认，同时允许开发者修改。本批提供按字段解析的优先级：**局部配置 → 主题角色配置 → 控件预置**。原有 Mica/Acrylic 固定配方继续默认使用；原生效果需要明确选择。没有安装、替换或停止 Fluent IME。运行时代码和示例已本地提交为 `6f355df`；标题栏几何修复为 `d42b101`。

## 实现范围

- 新增 `FluentMaterialConfiguration`，可选择材质、tint、fallback、AppKit blending mode 和局部启用状态。
- 主题角色覆盖 window/navigation/transient/toolTip/container；Tooltip 继承 transient，然后应用自身角色。主题复制和子树配置保留其他设置。
- `FluentMaterialSurface` 支持运行中修改角色、材质、圆角和边框；`.materialBackground` 提供通用背景入口；Card 默认保留普通填充，仅在局部或 container 配置明确启用时使用材质。
- 窗口场景默认 `.automatic`，允许主题 window 配置生效；显式 `.mica` 仍是局部选择，`nil` 仍表示无材质面。WindowShell 的既有 `.liquidGlass` 兼容别名仍保持 Mica 语义，通过角色配置选择实际 Glass。
- 菜单/ComboBox/其他共享 popup、Tooltip、日期时间颜色浮层、Sheet/Popover、ContentDialog、TeachingTip、导航/Inspector 接入同一配置解析。ContentDialog 的预置内容填充不会盖住明确选择的原生材质或颜色覆盖。
- 全局关闭、降低透明度和高对比度优先。透明 fallback 在明确色彩空间内与主题窗口底色合成，不再把低透明度白色直接变成不透明白色；高对比度采用语义底色。
- SettingsCard/Expander 等具有自身填充的控件没有被统一强制透明；通用背景也不会擦除嵌套控件的自有填充。

## 独立复现与修复

| 路径 | 修复前证据 | 本批结果 |
| --- | --- | --- |
| Surface 动态配置 | 要求 nativeAcrylic/20pt/无边框，却保留 mica/4pt/1pt | 原生实例保留，配置按新值更新 |
| Tooltip 材质 | 主题明确指定 Glass，仍固定 Acrylic | 共享主题角色配置，局部角色可覆盖 |
| 原生 Glass 圆角 | 外层 12pt，内部默认 8pt | 内外均为 12pt，后续更新同步 |
| 高对比度 | 仍为 visualEffect backend | opaque fallback |
| 辅助显示通知 | 正确的 workspace 中心通知未触发材质刷新 | 材质与 WindowShell 改用 workspace notification center |
| tint 覆盖前景 | 实际合成中 Native Acrylic/Mica 的红色色块被 tint 改色 | tint 保持背景层顺序，前景不变 |
| 普通刷新重复切换原生效果 | 本批初版使 Mica/Glass 每次刷新先切到 native material 再切回 inert material | 一次解析最终 backend，仅在值变化时赋值 |

`before.json` / `after.json` 复测前四项。通知见 `notification-before.json` / `notification-after.json`。Apple 明确要求在 [NSWorkspace 的通知中心](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayoptionsdidchangenotification) 注册，否则收不到该事件。

**修正一次错误的排除结论：** 最早未挂窗的图层探针不可靠；挂窗后的 `CALayer.render` 又显示前景红色未变化，一度排除了 tint 覆盖假设。后续 ScreenCaptureKit 合成捕获的有/无 tint 对照确认问题仍存在：Native Acrylic/Mica 前景分量最大差约 0.10。不能用离屏 layer.render 结果替代合成结果。原始探针、数据和阶段日志均保留。

合成证据：初版 16 个状态在 `compositor/`；修复前 12 个有/无 tint 对照在 `compositor-tint-before/`；修复后扩为 Mica、Acrylic、Native Acrylic、Native Mica、Glass 的深浅色，共 20 个状态。10 对前景差均为 0，背景仍有 9–31 个字节值的差异，证明 tint 仍生效且不再染前景。见 `compositor-verification.json`。颜色只做同一捕获环境下的配对比较，不将设备颜色分量直接当成 Windows sRGB 色值。

这些图像来自 `SCShareableContent.currentProcess` 限定当前进程的合成捕获，背景也由独立探针创建。它们验证图层、颜色覆盖和回退，不代表桌面壁纸或跨显示器取样验收。原生材质的最终采样、版本差异仍归 AppKit 管理。

## 刷新成本复核

`MaterialUpdateAudit.swift` 对同一 Surface 更新文本、布局、显示并 flush；每种材质预热 20 次、采样 200 次。Release 原基线和最终实现各交替运行三次，下表为三轮中位数的中位数（ms）：

| 材质 | 原基线 | 最终 |
| --- | ---: | ---: |
| Mica | 0.211 | 0.216 |
| Native Acrylic | 0.223 | 0.221 |
| Native Mica | 0.236 | 0.239 |
| Glass | 0.251 | 0.245 |

本批初版 Mica/Glass 单轮中位数曾升至 0.438/0.455ms；定位并消除了重复 native material setter 后回到上述水平。新增 KVO 回归测试验证未改变配置的刷新不会重建原生效果。所有轮次和初版数据保留；这些是模拟更新处理时间，不是物理键盘延迟，也不构成长期帧时保证。

## 验证结果与边界

- 最终 **472 项 XCTest，0 失败**：`full-tests-final.log`。
- `FluentKitValidation: PASS`：`native-validation-final.log`。前两次失败是验证器仍要求 `tintColor` 存着隐式 Mica 默认 tint；新 API 的该字段仅表示显式覆盖，已改为同时核对 nil 和默认 tint 层隐藏，保留默认固定配方行为。
- Gallery Debug 构建通过：`gallery-build-final.log`。
- Release 质量门禁通过：`quality-run.log` / `quality/`。固定入口加入新 Gallery 示例编译依赖。
- 动态 Surface 回归包含原生编辑器、marked text 和内容身份保留；原生 Glass 圆角、Card opt-in/撤回、角色继承、子树隔离、主题复制、fallback 和通知链均有检查。
- CUA 在实际 Gallery 搜索 SystemBackdrops，输入 `Material state retained`，选择 Liquid Glass，确认文本仍在；菜单打开后 AX 显示 `A menu item`，Escape 后恢复 Closed。
- 实际页面另发现 ComboBox 面板文字裁切，以及三个 FluentToggle 未出现在 AX 树中，已独立排队。当前浮层的 CUA 截图返回了不可靠的缩小主窗图，未据它声称菜单像素验收通过。

未完成：真实系统辅助显示偏好切换、真实鼠标悬停、高刷/复杂页面帧时、Windows 对拍、多显示器/不同缩放和壁纸切换、真实中文 IME 与完整 VoiceOver。此前的队列和原始审计范围继续保留。
