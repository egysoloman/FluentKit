# Tooltip 动画测试的关闭等待

基线：`ae7d469707a768025d4d6a0e75c7e3671286d6ec`。本批只修改测试，运行时和动画时长不变。

## CI 失败及复现

[CI #18](https://github.com/egysoloman/FluentKit/actions/runs/41292393449) 执行 525 项测试，1 项平台能力跳过，1 项失败。TeachingTip 的 9 项测试全部通过；失败点是 `ToolTipMotionTests.testContinuousToolTipReusesSurfaceAndRetargetsFromIntermediateFrame` 最后的关闭断言。原始日志保留在 `../teaching-tip-lifecycle/ci18-failure.log`。后续 Release 与质量门禁因测试失败未执行，不能记为 CI 通过。

该断言固定等待 400ms。运行时先在主队列等待 120ms 的离开宽限期，再开始 180ms 的淡出；第二段的起点取决于第一段回调实际执行的时间。主循环稍晚处理回调，就可能超过测试的固定等待。

在离开后 60ms 排入一次 300ms 的主线程停顿，旧断言在本机产生相同失败，见 `DelayedFixedWaitTests.swift.txt` 和 `before-tests.log`。这证明固定等待会误判延迟调度；CI 没有逐帧调度日志，不能声称已直接测得其调度延迟或排除所有外部输入干扰。

## 修改及检查

- 保留上述延迟回调场景，使用已有 `waitForUI`，在 2 秒上限内等待窗口解除父子关系。
- 保留全部运动中途、重定向、内容身份、位置与透明度断言；另检查面板不可见、没有父窗口、内容已经拆离。
- 相关 9 项测试通过，原始结果见 `targeted-tests.log`，无 AppKit 约束冲突。
- 最终完整 525 项测试全部通过，耗时 80.721 秒，无 AppKit 约束冲突，见 `final-full-tests.log`。初版修正的完整通过记录另保留在 `full-tests.log`。
- 延迟回调使用 expectation 确保在本项测试内结束，避免外部输入提前关闭面板时把停顿带到后续测试。
- 本批是测试改动，未重跑无需变更的 Gallery/Release 构建；后续 CI 仍执行完整原有流程。未修改运行中的 Fluent IME。

此测试验证关闭和资源清理，不能代替真实输入、帧时或跨系统动画验收。
