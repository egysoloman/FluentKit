# Toggle 可访问性与包装层语义

基线为 `bc28218`。此前 ComboBox 修复已提交，本批继续验证实际 Gallery 的三个开关为何不在 AX 树里。未修改、安装、替换或停止 Fluent IME。

## 对照与根因

- FluentToggle 设置了 checkBox role，但 `isAccessibilityElement` 为 false；直接实例与绑定实例均如此。
- 值返回英文字符串 On/Off，缺少状态变化通知。
- 本机 NSSwitch 实测为 `AXButton` / `AXSwitch`、数值 0/1，角色描述由系统生成。本批采用相同的公开角色/子角色和数值语义，未把私有 NSNumber 实现类名作为接口契约。
- 固定 WinUI 源码 `ToggleSwitchAutomationPeer_Partial.cpp` 的 GetAutomationControlTypeCore / ToggleImpl / get_ToggleStateImpl / RaiseToggleStatePropertyChangedEvent 对应按钮类型、禁用拒绝、On/Off 状态以及状态变化事件。源码 SHA-256 保存在 `winui-source-sha256.txt`。
- Apple 提供公开的 [switch 子角色](https://developer.apple.com/documentation/appkit/nsaccessibility-swift.struct/subrole/switch)。本批的具体值类型以实际 NSSwitch 和 Core Foundation 类型检查为证据，未将通用 NSAccessibilitySwitch 协议的历史字符串签名误当成 NSSwitch 的运行时值。

## 修复范围

1. Toggle 暴露为单个 switch 元素，返回数值状态，变化时发布原生 valueChanged 通知；保留原有绑定与操作链。
2. 实际交互验收发现标签/提示/标识符停在绑定或布局包装层。只有明确声明为透明的包装器转发元数据；显式语义 group 不因只有一个孩子就被拆掉。
3. `.accessibilityHidden()` 改为控制整个子树的 AX 发布，恢复时保留原生实例、布局和原有语义边界，不改视觉可见性。
4. 显示隐藏内容、accessibilityGroup 及 `.accessibilityElement(children: .contain)` 使用 AppKit 的 unignored children，省略内部包装器，按当前子树查询；ForEach 的具名 Items 分组继续保留。
5. combine 收集原生控件视图上的显式标签，同时跳过隐藏子树。原生控件的 AX 对象可能属于 cell，不能仅凭视图自己的 isAccessibilityElement 丢弃标签。

## 独立与交互证据

- `ToggleAccessibilityAudit.swift` 在自己的窗口中对照直接 Toggle、绑定 Toggle 和 NSSwitch。初始、按辅助操作、禁用操作、外部重置共 8 个 Fluent 状态；修前 8 个不符合公开契约，修后归零。`before.json` / `after.json` / `comparison.json` 保留原始字段。
- `gallery-before-ax.txt` 是实际 Gallery 的完整树，三个开关缺失。最终重新启动 Gallery 后，`gallery-after-ax.txt` 显示三个 switch；按元素定位切换 Teal tint 后数值从 0 变为 1，见 `gallery-toggled-ax.txt`。
- `ToggleAccessibilityApp.swift` 提供可见模型值和写入计数。CUA 按元素定位切换：绑定写入从 0 到 1；外部关闭后值恢复 0，计数仍为 1；禁用控件保持值 1；直接控件计数只增加一次。
- 实际树确认自定义名称出现、隐藏项消失和恢复、Named group 直接包含 switch。原始缺陷和中间状态在 `wrapper-before-ax.txt`、`group-before-ax.txt`、`interactive-first.json`；最终操作见 `interactive-final.json`。
- CUA 的 click 验证真实 UI 操作和系统树结果；直接 accessibilityPerformPress 的行为另由原生探针/回归验证，不假定 CUA 的内部点击传输方式。

保留早期失败记录：初版比较错误要求两个 NSNumber 的私有类名完全相同，现只检查公开角色、值和序列化类型；首次完整测试发现 combine 标签回归和错误地将 ForEach 语义分组当作透明容器的测试假设，均分别修正。挂窗后的原生 cell 路径又由新增测试覆盖。原生验证中旧的“仅有一个原始 stack 子节点”检查改为两个有意义的原生元素；AppKit 可能返回 cell proxy，因此不强转为 NSView。

## 重跑原生探针

先构建相应版本的 FluentKit，再运行 `zsh run-native.sh <SwiftPM products 目录> <新的输出目录>`。脚本只构建并运行自己的验证窗口，不操作用户应用。历史基线为 `bc28218`；交互应用源码单独保留，真实 UI 操作记录来自 CUA。

## 验收和边界

- 新增回归覆盖原生 switch 语义、绑定、禁用、重绑定身份、透明包装元数据、隐藏/恢复布局、动态语义分组、combine/contain 组合。
- 最终完整测试 484 项、0 失败；包括 8 项新增 Toggle/包装语义测试。最终相关 15 项测试通过，见 `targeted-tests-final.log` / `full-tests-final.log`。
- Gallery Debug 构建和实际开关操作通过，Release 质量门禁通过，见 `gallery-build-final.log` / `quality-run.log` 及 `quality/`。
- 原生完整验证补齐队列同步后连续两次串行通过，见 `native-validation-barrier.log` / `native-validation-barrier-repeat.log`；以下保留未补同步时的失败，不把两次 PASS 扩展为所有负载条件下的稳定性证明。
- 原生通知调用已补齐；尚未完成真实 VoiceOver 的朗读与通知接收验收，不以 AX 树验证替代它。
- 原有 Expander/Refresh 初始化警告继续保留。阅读源码另发现 Toggle 键盘提交时机与 WinUI 不同，列入第 27 项独立复现；本批范围为辅助操作和语义发布。
- 多显示器/缩放/壁纸、真实 IME 与触摸等原有队列继续保留。

## 原生验证同步复核

本批未补同步的原生完整验证分别停在 ToggleButton 按下、ComboBox 重新打开、editable ComboBox 入口动画、RepeatButton 更新检查；旧源码 `aad6d45` 的独立验证二进制也停在 Segmented 绑定更新，记录为 `native-validation-old-baseline.log`。不同断点的失败不能直接认定为 Toggle AX 运行时回归，也不能因旧版本也失败就忽略。

`drainMainQueue()` 原来只有一次 20ms RunLoop 区间，没有确认主队列已执行到已排队的绑定/渲染工作之后。本次验证程序先排入并等待主队列标记（1 秒超时即失败），再保留原有 AppKit settling 区间；没有延长动画、改控件实现或放宽任何状态断言。同步修改位于验证程序，不在框架运行时。最终通过说明这一版验证程序可完成全链路，但不是对每个早期失败根因的独立证明。

附加诊断对 Toggle 状态/颜色、ComboBox 窗口状态保留原始输出；`validation-diagnostics.patch` 为仅加诊断的补丁。缩短到 ToggleButton 阶段的 6 次 probe 均看到主队列标记在 20ms 区间内执行，因而没有把“每次 RunLoop 都漏执行队列”作为结论。它也说明不能以短探针成功替代完整验证。
