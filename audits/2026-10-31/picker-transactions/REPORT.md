# TimePicker / DatePicker 事务与本地化修复（2026-10-31）

本批在 `9cb213f` 基础上继续。没有改写此前的审计报告或原始数据。

## 范围

- TimePicker 弹窗由原生 `NSDatePicker` 时间编辑器改为与 DatePicker 共用的 Fluent
  LoopingSelector 列；编辑器拆到 `FluentTimePickerEditor.swift`，关闭态与弹窗共用
  `FluentTimePickerPresentation`（字段顺序、时段文字、数字格式）。
- TimePicker 新增 `locale`，从渲染上下文传入；字段顺序跟随区域模板（如 zh_CN 的 12 小时制
  时段在前），RTL 下先交换时/分再整体反转，使数字对仍按"时 分"阅读。
- 绑定：替换绑定后，旧绑定已排队的通知按代次丢弃；绑定为 `nil` 时不再被回退值覆盖；
  分钟步长归整后的值写回绑定。DatePicker 获得相同的代次隔离和写回。
- 配置原子化：父视图同时更换绑定、步长、时钟时先完成配置再应用选择，不再以中间状态写绑定。
- 弹窗事务：未改变的父视图更新保留草稿；外部绑定变化同步到打开的编辑器；Escape 丢弃草稿、
  Return 提交；已关闭弹窗中残留的控件不能再写入；禁用控件时关闭弹窗且不提交。
- 键盘：打开即聚焦首列，左右键在列间移动，Tab 依次到达 Accept、Dismiss 再回到首列。
- DatePicker 修正：`date` 别名与范围约束后的 `selectedDate` 保持一致；约束后的值会继续传播，
  此前在 didSet 中提前 `return` 导致不传播。
- 分钟步长为 0 时分钟列只有 "00" 且不循环。
- Gallery：DatePicker 示例改为 WinUI 分段 DatePicker，CalendarDatePicker 单独示例，新增
  TimePicker 示例；DatePicker 覆盖状态由 implemented 降为 **partial**，TimePicker 为 partial。
  Gallery 注册检查断言三者挂载了正确的原生类型。

## 验证（`run.sh`，结果在 `results/`）

- `swift test -Xswiftc -warnings-as-errors`：**165 项通过**，其中新增 `PickerRegressionTests`
  7 项（[tests.log](results/tests.log)）。
- [质量门禁](results/quality.log)：Release 更新次数、挂载身份、外部重置、排版和材质检查通过。
- [交互审计](results/interaction.json)：light(en_US)、dark(zh_CN)、RTL(en_US)、arabic(ar_SA)、
  24hour(en_GB) 五组，各 8 个状态，共 40 张实际渲染图；全部断言通过。
- [原生验证](results/native-validation.log)：`FluentKitValidation: PASS`。
- [完整 Gallery 构建](results/xcode-build.log)：`BUILD SUCCEEDED`，关闭签名。

人工查看了 dark(zh_CN) 初始弹窗和 arabic 提交态截图。

## 局限

- 未保留修复前的失败日志：新测试依赖新增的 `locale` 等 API，无法在旧实现上编译。
- 截图记录中 VoiceOver 与 Windows 对照仍为 `pending`。
- LoopingSelector 列内文字对齐、滚动惯性等未与 WinUI 逐像素对照，因此仍为 partial。
