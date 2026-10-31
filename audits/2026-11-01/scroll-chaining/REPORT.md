# 首尾滚动传递与共享输入事件复核

基线 `b85dcd1`。macOS 27.2 / Swift 6.4（Swift 5 模式）。原始历史审计保持不变。

## 独立复现与依据

WinUI 本地 release-2.3.1 的 `src/controls/dev/CommonStyles/FlipView_themeresources.xaml:87–88`
开启水平、垂直滚动传递。原实现会捕获首尾向外的新分阶段手势并弹性返回，父级收不到。
共享 pan driver 在判定轴向前还会吞掉小幅起始事件；随后拒绝跨轴手势时，父级仅收到 changed，丢失 began 和位移。

`before/regression-tests.swift` 三项回归产生 18 处失败（`before/tests.log`）。
公开 API Release 探针的 16 种嵌套 FlipView 组合中，修复前父级翻页成功 **0/16**。
基线复用上批 Release 库，SHA256 与 `audits/2026-10-31/pointer-popup-density/after/library-sha256.txt` 一致；
该批至 `b85dcd1` 仅新增审计文档。

## 修改

- FlipView 在稳定首/末页拒绝获取向外的新手势，向内翻页继续由自身处理；已有部分页或动画可重新抓取。
- 共享输入层暂存未判定的原始 NSEvent，拒绝、未达阈值就结束/取消时先依次转发，再转发当前事件。
  保持事件对象、时间戳、阶段、位移；拒绝后的惯性尾部也交父级。
- FlipView、Pivot、SwipeControl 全部显式提供 responder 转发函数，避免调用者遗漏历史事件。
- 连续微小往返抖动最多缓存 32 个事件，之后整段转交；这是本地防御策略，不是 WinUI 常量。
- 触屏 recognizer 同样检查获取方向；没有声称在物理触屏验收。

## 验证

- 新增 8 项回归；全量 **353 tests, 0 failures**。共享输入/FlipView/Pivot/SwipeControl 专项 58 项通过。
- 原生验证 PASS、Xcode Gallery BUILD SUCCEEDED、Release 质量门禁通过；`after/` 保留日志。
- 同一 Release 探针修复后父级翻页 **16/16**，内层选择保持不变；覆盖 Light/Dark × LTR/RTL × 水平/垂直 × 首/末页。
- 每组初始、70% 拖动、释放三个真实 layer-tree 状态，共 48 张 PNG；`check_results.py` 检查父级选择与拖动双页几何。
- 修复前后 16 对初始图完整 RGBA 像素一致；人工查看水平拖动裁剪和垂直 RTL 释放图。构建产物 SHA256 各自记录。
- 原始事件对象身份回归还覆盖惯性、跨轴、取消、拒绝获取、微小手势和 1,000 次交替抖动。

`ScrollChainingAudit.swift` 只使用公开 API，将事件直接发送至嵌套 FlipView；
没有向 NSScrollView 注入合成事件。这验证真实原生控件的 responder 传递与渲染，不能代替物理触控板验收。

复跑：`./audits/2026-11-01/scroll-chaining/run.sh /tmp/scroll-chaining-new`，然后
`python3 audits/2026-11-01/scroll-chaining/check_results.py /tmp/scroll-chaining-new`。
请使用新输出目录，保留已提交证据。

## 仍待完成

已获取的同轴手势在中途到达边界后，剩余位移与惯性尚未移交；精确 DirectManipulation 物理、
完整 item-container 语义、按钮图形/材质/按压、Windows 像素对拍、物理触屏和真实 VoiceOver 仍未完成。
本批不将 FlipView 标为完整实现。
