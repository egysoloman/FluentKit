# FluentKit 独立复核与修复记录

本轮覆盖原报告 15 项，以及后续补充的省略号拉伸和 AppBar 箭头重叠。先用修改前源码独立复现，再实施修复；原始 [REPORT.md](REPORT.md) 和原始数据未覆盖。处理全部条目不代表全部视觉还原工作已经验收。

## 证据与结论范围

- [independent-baseline/](independent-baseline/)：本轮改动前独立重跑原脚本所得 Release 数据。
- [repaired/](repaired/)：当前修复版同一负载的原始 JSON、AppKit 日志、Gallery 注册检查及截图。
- [AuditRegressionTests.swift](../../Tests/FluentKitTests/AuditRegressionTests.swift)：新增行为、工作次数、编辑冲突和几何回归。
- [run-repairs.sh](run-repairs.sh)：复现入口，包含明确的失败门槛；耗时保留为测量值，不设机器相关的绝对通过线。

独立复现确认原报告最严重的五项成立。17 倍兄弟更新来自嵌套宿主分开设置 context 与 content；原生实例反复移除并不代表每次都创建了新实例。列表原始行更新数表明它仍在虚拟化，但重复更新和原生快照操作把成本放大，不能描述成每个输入都创建全部 5,000 个行视图。

这些时间是模拟文本改变之后绑定、刷新和布局的处理时间，不是物理键盘到屏幕的延迟。基准保留同一机上的修复前后测量，不能直接推广到所有机器。

<!-- METRICS_START -->
| Release 场景 | 本轮修复前均值 | 修复后均值 |
| --- | ---: | ---: |
| 普通页面，100 个稳定视图 | 2.28 ms | 0.89 ms |
| 窗口壳，100 个稳定视图 | 14.81 ms | 6.75 ms |
| 窗口壳和侧栏，100 个稳定视图 | 37.80 ms | 8.32 ms |
| 窗口壳，5,000 项虚拟列表 | 125.47 ms | 4.29 ms |

普通输入各测 30 次，列表各测 10 次。100 行 shell/nav 的行更新总数由 **51,000 → 3,000**（17 次 → 每输入 1 次遍历），同一原生实例移除/挂载回调由 **1,020 → 0**。5,000 项列表的可见行更新由 **3,060 → 180**。这些是工作量下降，不能解释为框架不再刷新任何稳定视图。
<!-- METRICS_END -->

## 逐项处理

| # | 处理结果 | 证据与边界 |
| --- | --- | --- |
| 1 重复刷新 | 宿主加入原子的 `update(content, context:)`，修改嵌套宿主调用，合并排队刷新。绑定内部读值不再意外订阅整个渲染树。 | shell/nav 下每次改变只更新稳定行一次；仍会更新一次，尚无逐叶节点的任意依赖图优化。 |
| 2 原生实例反复挂载 | 相同原生实例原位保留；增加 `FluentNativeView(make:update:)`，创建与配置分开。 | 原复现的移除/挂载回调为 0。工厂在 mount 时执行一次。旧 autoclosure 每次产生新实例仍按新实例处理。 |
| 3 外部重置失效 | 焦点编辑期间同步模型和 field editor，取消已排队的旧文本发布；保留并裁剪选区。组合阶段收到外部值时延后应用，组合结束后外部值优先。 | 焦点中、失焦后的界面和模型均为 external reset；覆盖 closure binding、绑定替换、验证 setter 路径以及显式重复值 `.send()`。 |
| 4 列表全量快照刷新 | 结构不变不应用 native snapshot；只配置可见行。新增 `contentVersion` 支持不变可见内容跳过配置，主题/语言等环境改变仍刷新。 | 原 5,000 项 shell 复现中 10 次输入只更新 180 个可见行实例，不新增行、不重新挂载。ID 数组创建、结构比较仍为 O(n)。版本必须包含行内容捕获的依赖。 |
| 5 Mica 自动变成 Liquid Glass | 移除隐式替换，`.mica`/`.acrylic` 使用固定、可预测的底色；`.nativeMica`/`.nativeAcrylic` 与 `.liquidGlass` 明确选择系统效果。默认 transient 为 Acrylic。 | 路由缺陷已修。**固定底色是近似，并没有实现 Windows 壁纸采样、模糊与噪声合成；完整材质还原未完成。** |
| 6 字号/字重 | 使用 Caption 12、Body 14、BodyLarge 18、Subtitle 20、Title 28、TitleLarge 40、Display 68，补 strong 样式和旧名映射；标题栏 Caption 恢复 regular。允许字体提供器和逐样式 size/weight/lineHeight。 | 数值对照仓库中的上游 TextBlock/TitleBar 资源。默认仍是 macOS 字体，不附带 Segoe；字形、基线、换行与 Windows 对拍尚未验收。 |
| 7 图标来源 | 统一 `FluentIconSource`：SF Symbol、字形、NSImage、CGPath，提供着色、对齐、RTL 镜像及等比缩放。接入菜单、导航、标题栏、AppBar 和 CommandBar。 | 老 image/systemImageName 接口继续可用；原色图像不套模板色。彩色文件夹等应用资源仍由应用提供。 |
| 8 输入样式无差别失效 | 用可比较的 appearance 分离尺寸和颜色更新；绘制前同步字体；避免相同 style/controlSize/placeholder 再次触发尺寸失效。 | 同样式重复赋值无 intrinsic-size invalidation；同时修正富文本占位符导致普通 placeholderString 为空的问题。 |
| 9 IME 提交策略 | 新增 continuous/committedText 策略及包含 isComposing 的编辑事件；AutoSuggestBox 用提交后的文本调度建议。 | 模拟 marked text、结束组合和组合中外部重置有回归；兼容默认 continuous 仍允许组合串进入模型。真实拼音候选窗、选词、切换输入法未人工验收。 |
| 10 ForEach 全量排列 | 按稳定身份增量插入、移除、移动；稳定顺序不修改排列。去掉逐项全表 contains。 | 检查稳定更新及重排后的身份/挂载；ForEach 仍是非虚拟容器。 |
| 11 相等状态通知 | 具体 Equatable 值默认去重，公开比较器；`.observableValue.send()` 保留强制发布能力。 | 重复值、强制发布和禁用比较器的路径均覆盖。泛型调用若未提供等值能力，仍保持保守通知。 |
| 12 输入框全局监视器 | 右键 monitor 仅在编辑会话需要时注册，失焦/移出/释放时移除；非编辑右键直接由控件处理。 | 未编辑的字段不增加应用级 monitor。此项是右键分发/生命周期问题，不能当成键盘延迟直接证据。 |
| 13 默认文案 | 打包 en/zh-Hans/zh-Hant 资源；编辑菜单、标题栏/窗口按钮及常用控件默认辅助功能文本读取宿主 locale；应用 FluentKit.strings 优先。 | 覆盖中文、环境切换及应用覆盖；应用自己设置的辅助功能文本不被框架默认值覆盖。真实 VoiceOver 朗读和完整控件组合仍需验收。 |
| 14 Gallery 覆盖标记 | 建立 33 项直接样例的穷举注册；implemented 条目必须有直接样例；修正陈旧 missing/implemented 标记。 | 121 条目录现为 24 implemented、66 partial、17 platformAlternative、11 missing、3 notApplicable。33 个直接样例各在 light/dark/RTL 挂载检查；不是完整控件状态/行为完成率。 |
| 15 测试质量维度 | 增加输入次数、原生身份、外部重置、长文本撤销重做、标记文本、窄窗口、图标/箭头几何及资源回归；Release 工作次数门禁接入 CI。增加真实 AppKit 状态截图与像素比较脚本。 | 像素比较要求 OS/缩放/字体环境一致，比较器不会更新基线。旧 Gallery PNG 保留为历史记录；新图不是 Windows 参考图。 |
| 16 省略号变竖椭圆 | More 按源图像宽高比居中绘制；图标槽与图像绘制尺寸分离。 | 新浅色/深色 normal/hover/pressed/disabled 截图可见圆点；模板和宽图/路径测试覆盖比例。 |
| 17 下拉箭头贴文字 | AppBar 共用测量/绘制几何，给 chevron 单独留 8 点宽及 8 点间隙；覆盖 RTL。菜单变化使测量失效。 | 几何断言与截图均验证间距。保留默认 AppBar 48 高契约，提供 `commandHeight` 可选密度；32 高需宿主明确选用。未把正常禁用的“属性/压缩”改为可用。 |

## 独立发现的额外问题

1. 只修宿主原子更新后仍会剩下额外刷新：绑定协调器内部读取 observable 进入了渲染依赖追踪。现在内部读值不参与追踪，使用其已有观察通道同步，回归要求精确一次更新。
2. 长文本原生 undo 会恢复 editor/field，却没有总是把结果发布到模型。现在监听当前 editor 及其 UndoManager 的编辑/撤销/重做通知，合并重复发布；8,000 UTF-16 单元的选区替换、undo、redo、外部清空均有检查。
3. SplitButton 在瞬时零宽布局中使用过大的 inset 得到 null/infinite frame。对 primary 区域 inset 作尺寸限制后，Gallery 样例有限几何检查通过。
4. 输入框提前同步富文本 placeholder 后，AppKit 的 plain placeholderString 不再是可靠读值。primitive 更新此前可把自己现有占位符清空。现在比较实际显示文本并保留属性化占位符，新增同实例更新断言。

5. 切换为固定材质后，ComboBox 弹出层不能再依赖 native glass 带来的提前布局。现已在呈现前完成内容布局，确保立即可用的行命中区域；同步切换窗口主题的选择测试继续检查提交和关闭。

## 已验证与未关闭内容

最终运行结果见 [repaired/verification.json](repaired/verification.json)，测试/验证日志一并保存。截图分别为 [light](repaired/visual/audit-states-light.png) 和 [dark](repaired/visual/audit-states-dark.png)。检查了圆点比例、箭头间隔、禁用态、背景尺寸、文字裁切及材质路线。截图焦点列只验证 TextBox 活动 editor；Button 的键盘焦点、以及该列仍为普通状态的 AppBar/More 均未专项验收。

仍明确保留以下边界：

- AppKit CollectionView 在初次/过渡布局中仍输出 item width 超过可用宽度的警告，极窄窗口复现也会输出约束冲突警告。零宽构造、最终窄视口、滚动条、增量加载/选择回归通过，并不消除该观察。尝试过延后 document width 一致时才应用 snapshot，但这使无窗口宿主和 shell 显示受到影响，已移除该方案。此警告未关闭。
- 固定底色解决跨系统自动切换材质，不能冒充完整 Windows Mica/Acrylic；Segoe 字形和逐控件真实 Windows 截图对拍尚未完成。
- 真正中文候选窗操作、VoiceOver 和逐控件所有状态仍需专门的交互验收。自动化样例挂载不等于用户可操作性的全面验收。
- Explorer 同时重载隐藏列表和图标视图的应用层成本未在本仓库中修改；新增密度选择也需要该宿主采用。保留报告中的框架/宿主归因。
- 工作区开始时已有大量未提交改动；本轮在其上修改，未整体恢复或提交这些文件。`repair-source-manifest.json` 标识本轮验证所对应的源码内容。

## 复现

```sh
swift test --scratch-path /tmp/fluentkit-repair-tests -Xswiftc -warnings-as-errors
swift run --scratch-path /tmp/fluentkit-repair-tests FluentKitValidation
./audits/2026-10-30/run-repairs.sh /tmp/fluentkit-repaired-results
python3 tools/compare_snapshots.py .snapshots/audit-states /tmp/fluentkit-repaired-results/visual
```

Validation 的固定英文 fixture 在进程的 volatile argument domain 中设置 locale，不改变用户系统语言；本地化另有显式中英文和 bundle 覆盖测试。截图比较需要 Pillow，且只应比较元数据一致的机器环境。计数门禁不依赖截图环境，也不把一次低延迟当作通过理由。
