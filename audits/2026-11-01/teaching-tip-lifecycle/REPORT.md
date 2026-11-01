# TeachingTip 生命周期与根窗口重排

基线：`cd33892b2b7eb7dad082d54afadde1f5c27eca75`。接续多屏队列第 22 项；本批修复卸载和根窗口事件，不宣称完成真实多屏验收。

## 先修正审计判断

初看 `shouldConstrainToRootBounds == false` 跳过边界检查，容易误判为缺陷。完整上游路径却表明这是 WinUI 的默认契约（以下路径位于本地 `microsoft-ui-xaml-winui3-release-2.3.1/` 快照）：

- `src/controls/dev/TeachingTip/TeachingTip.h:227–228`：`m_tipFollowsTarget` 默认 false，`m_returnTopForOutOfWindowPlacement` 默认 true。
- 同目录 `TeachingTip.cpp:1805–1820`：允许超出根窗口时，默认直接采用首选方向（Auto → Top），说明原因是其多显示器信息限制。
- `DetermineEffectivePlacementTargeted`、`GetEffectiveScreenBoundsInCoreWindowSpace` 的屏幕回退算法在该模式下需要关闭这个测试钩子才会执行。

因此本批保留默认语义，没有擅自把测试钩子路径变成默认。相关控制测试验证浮层可以超出根窗口。最初用“必须超出物理屏幕”验证这一点的断言不成立：原生 NSPanel 首次显示时实际被 AppKit 下移到工作区顶部；该失败留在 `targeted-tests.log`，不作为框架缺陷统计，也不能据此概括所有轴向/多屏原生行为。

## 独立复现

`before-final-tests.log`：4 条测试、12 个失败断言。全部使用真实原生窗口，保留目标宿主引用，避免 deinit 掩盖问题。

1. 从层级移除仍被引用的目标：旧浮层继续可见并挂在原窗口，绑定仍 true，无 Closed。
2. 把目标加入另一窗口：旧面板留在第一窗口，第二窗口无法正常重新打开。
3. 关闭所属窗口：旧面板虽隐藏，仍有 parent，绑定未复位，也未发 Closed。
4. 所属窗口宽度增加 100pt：目标随 autoresizing 移动 100pt，浮层移动 0pt。

首次 `before-tests.log` 的第 4 条测试未开启手动 frame 布局（FluentViewHost 默认关闭 autoresizing-mask 翻译），目标本身没有移动。修正测试夹具后重新跑过旧运行时，才确认第 4 条真实脱锚；原始失败日志不删除。修正后的原始测试源码见 `BeforeTests.swift.txt`。

`TeachingTipLifecycleAudit.swift` 独立链接旧 Release 对象，仅用公开 API。浅/深色 × LTR/RTL × 卸载/换窗口/关闭/缩放 × 初始/变化后共 **32 状态**；12 个生命周期变化状态和 4 个缩放状态均失败（`before-check.json`）。图片只合成探针自己的图层，不包含桌面或其他应用。前后对象及探针哈希独立保存在输出目录。

## WinUI 依据与修复

参考同一仓库快照的 `TeachingTip.cpp`：

- `ClosePopupOnUnloadEvent`（1354–1358）直接设 IsOpen(false) 并 ClosePopup；经 OnPopupClosed 发 Closed。该卸载路径不等待或征询可取消的 Closing。
- `XamlRootChanged` / `RepositionPopup`（1546–1593）在目标布局结束后更新位置。不是把默认关闭的任意目标跟随测试钩子打开。

本批对卸载、换窗口、所属窗口关闭立即清理：先撤销观察器/鼠标 monitor、使旧动画代次失效并清掉所有权，再移除面板、复位绑定和发 Closed/Dismiss。开启动画的晚到回调、Closing 中移除目标后又请求取消，以及 Closed 中请求重新打开都不会复活旧面板；所属窗口已经关闭时，新的打开请求保持待处理，直到该窗口再次显示并触发同步。

根窗口与屏幕通知合并到下一主线程循环，完成布局后重排；保留现有位置选择规则、面板、内容和响应者。关闭后释放观察器，排队回调执行前校验面板身份。普通关闭也先清理所有权，避免 AppKit 调用重入重复发 Closed。

## 验证

- 最终完整 **525 项测试、0 失败**，80.421 秒；新增 9 项覆盖上述四条路径、开/关动画中卸载、Closing 重入、关闭窗口重开请求和默认出根边界契约（`final-full-tests.log`）。开/关动画测试先确认实际动画键仍存在，再卸载并等待超过其剩余时长，验证无晚到 Opened 或重复 Closed。此前 524 项完整通过的日志也保留（`full-tests.log`）。
- 最终 Release 构建通过，43.43 秒；Gallery Xcode 构建通过（`final-release-build.log`、`final-gallery-build.log`）。中间构建日志也保留。
- 原生验证 PASS；Release 更新次数、身份、重置、字号与材质门禁通过（`native-validation.log`、`quality.log`、`quality/`）。完整测试、原生验证和探针日志均无 AppKit 约束诊断。
- 修复后同一独立 Release 探针 **32 状态、0 失败**（`after-check.json`）。12 个生命周期变化状态正常清理、4 个缩放状态正常跟随，内容和响应者保持。人工检查确认目标移除后旧图层消失；前后共 64 张图全部保留。
- 上一批 ComboBox 的 [CI #17](https://github.com/egysoloman/FluentKit/actions/runs/41290897586) 已通过：516 项、1 项平台能力跳过、0 失败，所有作业步骤成功（`previous-batch-ci.log`）。这验证上一批，不代替本批待推送后的 CI。

```sh
zsh audits/2026-11-01/teaching-tip-lifecycle/run-native.sh <SwiftPM-products> <new-output-dir>
python3 audits/2026-11-01/teaching-tip-lifecycle/check_native.py <new-output-dir>/results.json
swift test --scratch-path /tmp/fluentkit-repair-tests -Xswiftc -warnings-as-errors --filter TeachingTip
```

本批没有安装、替换或停止 Fluent IME，没有调整显示模式。根约束模式的完整打开后回退/裁剪策略、可选屏幕约束策略、物理跨屏与混合倍率，以及 Windows 对拍仍继续核查。
