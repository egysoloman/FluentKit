# CalendarView 连续滚动与独立复核（2026-10-31）

基于 `e1c3300`，继续 CalendarView / CalendarDatePicker 的 WinUI 对齐工作。历史审计数据不变。
本批覆盖连续网格、日期索引、键盘焦点和共享弹窗；控件仍标记 Partial。

## 修复前证据

[基线测试](before/tests.log)有 3 项测试、5 处断言失败：没有连续滚动视口；
January 31 的 PageDown 跳到 February 1 而不是 February 28；没有 WinUI 默认日期边界。
[Release 基线](before/results.json)记录浅色／深色、LTR／RTL、三个层级和四个阶段，共 48 个状态；
所有状态均没有滚动视口。原始 PNG 和实际链接对象的 SHA-256 一并保留。

## 参照的 WinUI 源码

来自本地 `microsoft-ui-xaml-winui3-release-2.3.1`：

- `src/controls/dev/CommonStyles/CalendarView_themeresources.xaml`：三层级 ScrollViewer + CalendarPanel。
- `src/dxaml/xcp/dxaml/lib/CalendarView_Partial.h`：月视口 2–8 周，默认 6 周。
- `CalendarView_Partial.cpp`：年／十年 4×4；只有月视图带前导空位；完整范围与小视口的翻页规则；
  层级变化先检查最后浏览日期是否可见，必要时采用首个可见范围内日期；CopyDate 保留较小日期字段。
- `CalendarViewGeneratorHost.cpp`：按前两个可见范围的覆盖比例选择标题，比例相等时保留前者。
- `CalendarView_Partial_Interaction.cpp`：Home/End 使用可见范围；PageUp/PageDown 从焦点日期增减范围。
- `src/dxaml/xcp/components/DependencyObject/DependencyProperty.cpp`：Gregorian 当前年份 ±100 的默认边界。

## 实现和额外发现

- 使用算术日期索引及有界单元池，按可见行加前后各一行生成视图；没有构造全日期数组。
  月／年／十年均连续滚动，父级重复更新和外部选择变化保留浏览位置。
- 复用时重置状态和回调，忽略此前开始的旧点击跟踪；离屏 first responder 保持原日期，
  按键将其带回可见范围。辅助功能子项只包含实际与视口相交的单元。
- 新增 `numberOfWeeksInView` 初始化参数（2–8、默认 6，越界值夹取）；改变视口大小保留顶部行，
  避免 NSClipView 的中间尺寸取整导致前一行突然出现。Gallery 展示两周视口和外部选择更新。
- 标题跟随可见范围。移动到相邻月的已可见日期时，焦点和标题各自保持正确含义；
  在远处滚动后切换层级不会回到旧年份。月份／年份激活保留日／月，非法日期夹取到有效日期。
- 未提供的日期上下界分别采用当前 Gregorian 年份 −100 的 January 1 和 +100 的 December 31，
  使用配置时区；更宽范围需要显式设置边界。范围外日期不生成单元。
- 独立复核发现，仅验证日期索引往返会漏掉 Samoa 跳日后的星期列偏移。月网格改用 UTC 中的
  同历法日期定位；本地不存在的日期留空，翻页遇到空位会继续寻找有效日期。测试同时检查日期唯一性、索引和实际星期列。
- 更新旧测试中“永远创建 42 个按钮”和固定槽位编号的假设，改为检查可见日期、屏幕坐标顺序
  和有界缓存；没有删除选择、时区、禁用、绑定和层级断言。

## 验证

环境为 macOS 27.2 / build 26B123、Swift 6.4，见 [环境记录](after/environment.txt)。
所有测试／AppKit 探针串行运行，最终运行时代码验证如下：

- [全量测试](after/swift-test.log)：**328 项、0 失败**；本批新增 11 项。
  覆盖 1000–3000 年范围内每层级 60 次跳转的复用上限、离屏焦点、2→8 周调整、
  绑定、RTL、日期边界、DST、Samoa 跳日及希伯来历 13 个月年。
- [原生验证](after/native-validation.log)：PASS；[Gallery 构建](after/gallery-build.log)：BUILD SUCCEEDED。
- [Release 门禁](after/quality.log)：更新次数、挂载身份、外部重置、集合、字号和材质检查通过。
- [48 状态数据](after/results.json)、[检查日志](after/probe.log)：12 种组合的初始、13pt 位移、
  远距离滚动、30 次相同父级刷新均通过；年／十年滚动按有效内容边界夹取。
- [Samoa 实际单元检查](after/date-arithmetic.json)：2011 年 12 月有 41 个可见日期，
  不存在的 30 日留空；2026 年 5 月的星期列亦正确。检查真实单元的横坐标与日期 weekday。
- [真实日期弹窗](after/popover.log)：单个 310×350 共用日历，13pt 连续位移，
  选择 May 12 后模型更新并关闭弹窗。已查看中文弹窗渲染图。

默认六周视口的 Release 记录（包含已挂载的隐藏缓存）：

| 层级 | 初始可见单元 | 本次最大挂载单元 |
| --- | ---: | ---: |
| Month | 42 | 63 |
| Year | 16 | 28 |
| Decade | 16 | 28 |

这些是视图数量和复用证据，不是物理输入延迟或整体帧率测量；八周视口需要更多缓存单元。

人工逐组查看了 [12 个初始状态](after/initial-contact-sheet.png)、
[12 个部分滚动状态](after/partial-contact-sheet.png)、[12 个远距离状态](after/far-contact-sheet.png)，
以及两个 Samoa 状态和中文弹窗。刷新后 12 张图与对应远距离图逐 RGBA 字节一致，
见 [像素检查](after/refresh-pixel-check.json)。日历专项目录共保留 52 张原始 PNG。

初次全量执行有两项 AutoSuggestBox 弹窗测试失败，保留在
[初次日志](after/swift-test-initial.log)。这两项在隔离复查中通过，见
[复查日志](after/auto-suggest-recheck.log)。本批未改 AutoSuggestBox 运行时代码，
尚不能确定这次波动的具体原因，不能将一次重跑通过视为已修复该波动。

## 重现

```sh
swift test --scratch-path /tmp/fluentkit-repair-tests -Xswiftc -warnings-as-errors
./tools/run-quality-checks.sh /tmp/calendar-scrolling-quality
./audits/2026-10-31/calendar-scrolling/run.sh /tmp/calendar-scrolling-audit
```

探针直接改变 clip 视口来稳定复现连续位移；运行时仍使用 AppKit 原生滚轮／触控板路径。
没有向 NSScrollView 注入合成 scrollWheel 事件，也没有据此宣称物理输入延迟或实机触摸验收。
图像由实际 layer tree 渲染；不使用 AI 图像或网页仿制。

可选：安装 Pillow 后运行 `python3 audits/2026-10-31/calendar-scrolling/inspect_images.py <输出目录>`，
生成汇总图并验证刷新前后 RGBA 字节。
原始三项失败测试另存为 [baseline-tests.swift](baseline-tests.swift)；在独立 `e1c3300` 工作副本中
将其复制为 `Tests/FluentKitTests/CalendarScrollingTests.swift` 后运行 `--filter CalendarScrollingTests`。
Release 基线可在该副本先构建旧版 FluentKit，再用 `AUDIT_USE_EXISTING_BUILD=1` 调用本探针；
通过 `FLUENTKIT_QUALITY_BUILD` 指定该副本独立的 Release scratch 目录，避免误用当前版本的构建产物。

## 仍未完成

WinUI 可选吸附点、范围标签和运动细节、完整多纪元行为、日项模板／密度标记、
逐像素 Windows 对照、真实触摸与 VoiceOver 验收仍待后续工作。
测试与当前 macOS 截图通过不等于 Windows 外观／辅助功能验收完成。
