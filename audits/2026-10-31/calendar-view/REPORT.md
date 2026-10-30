# CalendarView 独立复核与修复（2026-10-31）

本批在 `fce8b14` 基础上继续原审计任务。没有改写 2026-10-30 的历史报告或原始数据。

## 独立复核

Claude 关于“CalendarView 是 NSPopover 原生日历”的描述需要拆开看：修复前没有公开的
`FluentCalendarView`；但 CalendarDatePicker 的弹窗内容已经是自绘的 Fluent 网格，
`NSPopover` 只是外层容器。实际缺口是独立控件、选择模型、键盘行为和日期计算，而非全部使用系统日历。

以下问题先写复现，再修改实现：

| 问题 | 修复前证据 | 修复结果 |
| --- | --- | --- |
| 周起始日错位 | firstWeekday=2 时网格从周一开始，标题仍从周日开始 | 标题和日期列使用同一周起点 |
| 时区不一致 | UTC 的 Calendar 配合洛杉矶时区，2025 年 12 月视图点击 1 日却返回当地 12 月 31 日 | 格式化和日期运算共用显式时区 |
| 范围边界仍可翻页 | 范围仅覆盖 2026 年 5 月，前后导航按钮仍启用 | 只允许进入与有效范围相交的月／年／十年 |
| 日期输入绑定切换被旧通知覆盖，AX 值过期 | 切换到 5 月 15 日后，已排队的旧源通知把界面改成 5 月 11 日；后续新源更新时 AX 仍保留旧值 | 通知代次隔离、读取当前绑定值，并同步 AX 值 |

前三项产生 **3 个测试、4 个断言失败**，见 [before.log](before.log)。绑定问题另有
**1 个测试、3 个断言失败**，见 [rebinding-before.log](rebinding-before.log)。

WinUI 参照使用本地 `microsoft-ui-xaml-winui3-release-2.3.1`：

- `src/dxaml/xcp/dxaml/lib/CalendarView_Partial_Selection.cpp`：None/Single/Multiple 切换、
  点击已选日期移除同日重复项、设为 blackout 后撤销选择。
- `src/dxaml/xcp/dxaml/lib/CalendarView_Partial.cpp`：年／十年默认 **4×4**。
  原有实现和测试都写成 4×3，因此一并修正。
- `src/dxaml/xcp/dxaml/lib/CalendarView_Partial_Interaction.cpp`：方向键、范围 Home/End、
  PageUp/PageDown、Ctrl+Up/Down 层级切换。
- `src/controls/dev/CommonStyles/CalendarView_themeresources.xaml`：40pt 日单元、14pt 日期正文、
  半粗星期标题、8pt 上下导航符号、透明常态／选择描边／禁选划线。

## 本批实现

- 新增公开 `FluentCalendarView`，支持独立嵌入、绑定日期数组、三种选择模式、禁选日期、
  日期范围、首日设置、Month/Year/Decade、RTL 和键盘导航。
- CalendarDatePicker 使用同一网格，保持原有非可选日期 API：点击当前日期提交并关闭弹窗。
- 按历法日处理选择，保留多选模型中的同日重复项，取消该日时全部移除。
  模式／范围／禁选日期变化会同步归一化绑定。新增对夏令时和希伯来历 13 个月年的回归覆盖。
- 相同父视图参数不会重置浏览位置或触发日历布局刷新；观察者替换和移除会隔离旧通知。
- 删除未被使用的旧月编辑器以及被共用网格替代的旧编辑器，保留其余时间／颜色编辑器。
- Gallery 增加独立示例，覆盖状态为 **partial**，不因类型存在或测试通过改为完整实现。

实现过程的截图检查发现并修正了 NSButton 翻转坐标系导致的箭头反向，以及中文日期模板在日单元
附加“日”的问题；中文日单元现在使用本地化数字，AX 标签仍包含完整日期。

## 最终验证

- `swift test --scratch-path /tmp/fluentkit-repair-tests -Xswiftc -warnings-as-errors`：
  **158 项通过**，本批增加 11 项日历回归；更新了旧编辑器 4×3 的错误预期。
- [原生验证](native-validation.log)：`FluentKitValidation: PASS`。
- [完整 Gallery 构建](xcode-build.log)：`BUILD SUCCEEDED`，关闭签名。
- [Release 门禁](quality.log)：重复更新、挂载身份、外部重置、集合快照、字号和材质检查通过。
- [Gallery 注册检查](quality/GallerySampleAudit.json)：35 个直接示例均完成 light/dark/RTL 挂载，
  CalendarView 明确记录 Windows 对照和 VoiceOver 尚待验收。
- [日历状态记录](visual.json)：light/dark/RTL 各 7 个状态，共 21 张实际 AppKit 渲染图。
  人工查看了浅色月视图、RTL 年视图、深色禁用态及中文真实弹窗；未把所有图片等同于人工验收。
- [真实弹窗](popover.log)：日历 310×350，弹窗内容 326×366，选择 12 日后模型更新且弹窗关闭。
  独立探针使用可见锚点并查找实际 NSPopover 窗口；原 Gallery 的 child-window 截图入口未成功找到面板。
- [通用视觉基线](pixels.json)：两张既有 light/dark 组合图像素差均为 0。
  这是本机回归检查，**不是 Windows 逐像素对照**。

本次 Release 单次模拟输入记录（绑定、刷新和布局处理时间，不是物理键盘延迟）：

| 场景 | 平均时间 |
| --- | ---: |
| 普通页面，100 个稳定视图 | 0.884 ms |
| 100 个稳定视图，加窗口壳 | 5.936 ms |
| 100 个稳定视图，加窗口壳和导航 | 7.671 ms |
| 5,000 项虚拟集合，加窗口壳 | 4.223 ms |

原始值在 [InputAudit.json](quality/InputAudit.json) 和 [CollectionAudit.json](quality/CollectionAudit.json)。
稳定视图仍各执行一次更新回调：100×30 次修改共 3,000 次；挂载回调为 0。该数据不意味着更新成本归零。

## 尚未覆盖

连续滚动／虚拟化、完整多纪元边界、WinUI 所有日历格式和模板／密度指示、完整高对比度状态矩阵、
Windows 实机截图对照及真实 VoiceOver 尚未完成。当前 Month/Year/Decade 是分页网格，字体仍使用
项目已有的 macOS 回退机制。`displayDate`、`displayMode` 和无绑定 `selectedDates` 是初始值及
后续值变化请求；重复同一参数不会强制重置用户浏览。日期范围未指定时不模拟未经核实的 WinUI 默认范围。

重跑入口：`./audits/2026-10-31/calendar-view/run.sh /tmp/fluentkit-calendar-recheck`。
入口依次执行测试、Release 门禁、21 状态截图、真实弹窗交互和原生验证；Xcode 构建需另行运行。
编译环境和关键源码散列见 [environment.json](environment.json)。
