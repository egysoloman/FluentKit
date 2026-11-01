# Tooltip 淡出中途交接的 CI 等待

`9e8acd9` 的 CI #21 失败：544 项中 1 项平台能力跳过、1 个失败断言；新增锚点生命周期 11 项全部通过。已有 `ToolTipMotionTests.testContinuousToolTipCancelsOldFadeWhenOwnershipChanges` 在固定等待 50ms 后得到 alpha=1，未观察到淡出开始。原始日志 `ci21-failure.log`，run 41296976767 / job 124819763343。

失败日志没有逐帧调度跟踪，不能断言 CI 负载是唯一原因。测试改为限时等待实际 `0 < alpha < 1`，再交接给第二个宿主；仍明确要求已开始且未结束，不能用完成淡出代替中途状态。之后等待恢复 alpha=1 和新内容挂载，继续检查复用原面板、可见性及旧内容卸载。没有修改运行时或延长动画。

相关 9 项通过；本地完整 544 项、0 失败，91.264 秒，没有 AppKit 约束冲突。见 `targeted-tests.log`、`full-tests.log`。运行时未变，因此没有重复 Gallery/Release/原生门禁；该代码的最近一次验证在 `../popup-anchor-lifecycle/REPORT.md`。提交后 GitHub CI 仍需跟进，不能用本地通过替代。
