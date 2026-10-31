# FlipView 连续翻页及页面尺寸

2026-11-01。基线 `77d8f26`。这是 FlipView 的独立路径，和 `../page-motion/REPORT.md` 中 NavigationView/IME 动画分开验证。

## 确认的问题

1. 快速进行 A→B→C 时，旧实现先取消 A→B，将 B 的 transform 归零，再播放 B→C。尚可见的 A 被移除，B 从中途位置跳到中心；反向也发生位置突变。新增动态测试在旧代码上出现 12 处断言失败，覆盖水平、RTL 和垂直方向。Release 窗口探针的中断最大位置差约 **215pt**，另有 4 个仍可见页面被直接移除。
2. 页面宿主使用手动 frame，却仍关闭 autoresizing-mask 约束转换。其四边受约束的原生内容可以被布局为 **0×0**，背景不绘制。旧 Release 原生探针的 `contentBounds` 保留了该结果；这不是新动画造成的回退。

## 修复与行为

- 以可见视口位置连续推进，后续相邻选择从当前位置转向新目标。对页面使用 frame 位移，避免内容刷新重置其 layer transform。
- 仅保留可见的两个页面和目标的相邻缓存，最多 **5 个**；每帧不重复配置未变化的缓存集合。结束后恢复普通相邻缓存。
- 抓取仍在快速翻动的视口时，取消尚未到达的远处目标，将选择同步到眼前的页面邻域，再进行单页拖动/停靠。拒绝该选择的绑定会结束过渡，重入修改数据也会终止旧操作。
- 非相邻跳转（例如 Home/End 或模型直接跳至第 1,000 页）立即落位，避免沿途构建。此处参照 [WinUI `OnSelectedIndexChanged`](https://raw.githubusercontent.com/microsoft/microsoft-ui-xaml/main/dxaml/xcp/dxaml/lib/FlipView_Partial.cpp)：其动画入口区分相邻索引变化与其他跳转。
- 为手动管理 frame 的宿主开启 autoresizing-mask 转换，使内部约束获得实际页面尺寸。

非相邻跳转及抓取未完成序列时的选择同步是可见行为变化，已更新 API 文档及 CHANGELOG。原有测试中针对特定 CA 动画 key 的检查改为实际位置检查；“首个旧页面应立即隐藏”的旧断言也改为有界缓存，并由新增连续性检查验证仍可见页面必须保留。

## 结果

同一 Release 探针在修复前/后分别执行 **108 个状态**：水平/垂直 × LTR/RTL，包含连续两次翻页、反向、20 次快速连按、16 帧途中采样、跳到末页、缩放、结束和 Reduce Motion。

| 指标 | 修复前 | 修复后 |
| --- | --- | --- |
| 中断/反向最大位置突变 | 215.38pt | 0pt |
| 被丢弃的仍可见页面 | 4 | 0 |
| 原生内容初始尺寸 | 0×0 | 400×240pt |
| 缩放后原生内容尺寸 | 0×0 | 520×300pt |
| 第 22 页直接跳末页新建数 | 2 | 2；立即落位 |

修复后全部状态最多挂载 5 页，结束/缩放/Reduce Motion 均只有一个可见页面，位置和绑定一致；44 张背景完整性图片均通过。新增测试验证中途接手势、拒绝写入、回调重入清空数据及原生内容布局。

**384 项测试、原生验证、Gallery Debug 构建和 Release 质量门禁通过，无 AppKit 约束诊断。** 首次全量测试中，新增测试曾把本地化的空列表标签写死为英文；修为检查空状态与空内容，失败日志保留。先前阶段的 3 处 CA-key/立即隐藏断言失败也保留在 `after/test-initial.log`。

该实现复用框架的 60Hz 标量动画调度器与 250ms 曲线。高刷屏、复杂页面帧时、真实触摸、Windows 逐帧/惯性曲线对拍仍未验收；不能以此宣称物理手感完全相同。边界后剩余滚动传递仍在原计划中。

## 复现

```sh
swift test --scratch-path /tmp/fluentkit-repair-tests --filter FlipView
zsh audits/2026-11-01/flip-motion/run.sh /tmp/flip-motion-review/after
# 用 FLUENTKIT_FLIP_LIBRARY 指定旧 Release 对象后，同一探针输出到 before。
python3 audits/2026-11-01/flip-motion/check_results.py /tmp/flip-motion-review
```

`before/` 保留原对象哈希和原始失败；`after/` 是当前结果，`checks.json` 为机器比较结果。窗口图片直接渲染 layer tree。
