# 页面与返回动画：中断、缩放及实际设置页复验

2026-11-01。框架基线 `4947b93`。本批同时修复 NavigationView 与 IME 自己的动画实现；没有把两者误认为同一路径。

## 框架：快速切页会短暂清空画面

NavigationView 在 A→B 的进入阶段尚未完成时跳转 C，会立即移除仍可见的 A。逻辑上的当前页 B 此时还透明，C 也在等待进入，因而出现空白。

新增 `NavigationInterruptionTests` 在旧代码上复现：中断前仍有红色 A，第二次跳转后的红色像素为 **0**。Release 公共 API 探针也在 slide、entrance、bottomUp 的 LTR/RTL 路径复现；例如 slide-ltr 中断画面的有效像素原为 0，修复后约 57 万（60 万像素画布）。

现在仅在已有过渡被中断时，保存当前可见的合成帧作为离场内容，再进入最新页面。正常导航继续使用原有页面视图。离场图不接收鼠标事件，也不重复挂载旧页面的交互内容；目标页面保留其真实实例。尺寸或 bounds 改变时直接完成到最新页面，避免拉伸已冻结的图像。

`navigation-before/`、`navigation-after/` 使用相同 Release 探针，覆盖五种动画 × LTR/RTL × 六个状态，共 **60 个状态**。修复后所有缩放、结束、Reduce Motion 状态均只剩最新页面，无动画或快照残留。示例图中的白色位置标记和字母用于检查方向与图像上下关系。

## IME：截错画面、旧图尺寸滞后、返回按钮重新闪现

实际应用 `/Users/stars/Downloads/Fluent IME` 中的 `IMEPageMotion.swift` 存在独立问题：

- `cacheDisplay` 捕获模型视图，忽略正在播放的过渡。快速返回时，屏幕还是上一页，下一次使用的快照却已经是尚未出现的新页。受控红→绿样本清楚复现了这种不一致；现在取当前 presentation layer 的合成帧。
- 视口由 300pt 增至 420pt 后，旧图仍是 300pt，动画继续运行。现在几何变化时结束过渡；关闭窗口及取消时同时清理入场和离场动画。
- 返回按钮的真实控件已经隐藏时，旧图仍在淡出；快速再进入详情会丢弃这张图，并将按钮透明度重新设为 0。现在读取仍可见的旧图位置和透明度，再从该状态继续。

缩放、返回按钮中断与关闭检查包含在同一份修复前/后探针中。快照像素比较先统一 ICC 色彩空间；中断时模型图与可见帧的巨大差异消失，当前数值见 `checks.json`。两次采样之间仍会经过少量动画时间，不能把它当作逐像素静态相等。

实际设置页还有一个必须保留的正常场景：进入“常规”会出现滚动条，视口从 616pt 变成 599pt。现在以原始像素尺寸绘制并裁切旧图，保持这类正常导航动画；不会因这 17pt 变化停止所有切页，也不会把旧图横向压缩。

应用没有 git，本次仅修改 **IMEPageMotion.swift**；改前/改后哈希、可逆补丁 `IME-page-motion.patch` 已保存，反向 dry-run 通过。未安装、替换或终止已安装的输入法。

## 实际宿主及验证

- 直接编译实际设置源码，执行常规、按键、外观、词库四页的快速进入/返回、缩放、滚动后返回，共 **16 个状态**。普通导航均继续有过渡；缩放和结束后页面/标题栏动画归零。
- 独立测试 App 的电脑界面检查确认返回后首页正确、再进入按键页正确，最大化后背景覆盖整个窗口，搜索框保留圆角和对齐。打开组合框并 Escape 关闭后设置值保持不变。电脑工具不能可靠截取短动画的每一帧，因此用前述动态探针补充。
- 相同实际 Gallery 的 **100 个切页、Expander 和窗口状态**再次通过，200 个染色/遮罩几何采样无滞后；没有把背景与折叠布局修复弄回去。
- **381 项测试、原生验证、Gallery Debug 构建、实际 IME Release 构建、Release 质量门禁通过**，无约束诊断。

全量第一次运行曾有一项 AutoSuggestBox 预览断言失败，日志保存在 `after/swift-test-initial.log`，单独复查通过。该测试原先用固定 190ms 推断 180ms 防抖已完成；现在明确等待建议结果，并额外断言浮层已打开，再做预览检查。最终全量通过；未将单次失败猜测成新的运行时根因，也未删除失败记录。

[Microsoft 页面过渡指南](https://learn.microsoft.com/en-us/windows/apps/develop/motion/page-transitions)区分入口、层级深入、水平翻页和返回的用途。本批保留现有动画模式与常规时序，修复中断和几何连续性；不是 Windows 设置的逐帧对拍。系统级 Reduce Motion 实机切换、触摸硬件仍保留专项验收。FlipView 的独立手势/翻页实现不能用 NavigationView 的修复代替，仍在总计划内继续核查。

## 复现

```sh
swift test --scratch-path /tmp/fluentkit-repair-tests --filter NavigationInterruptionTests
zsh audits/2026-11-01/page-motion/run-navigation.sh /tmp/page-motion-review/navigation-after
zsh audits/2026-11-01/page-motion/run-ime-motion.sh /tmp/page-motion-review/after
zsh audits/2026-11-01/page-motion/run-settings.sh /tmp/page-motion-review/settings-after
python3 audits/2026-11-01/page-motion/check_results.py /tmp/page-motion-review
```

需要当前 Release FluentKit 及与实际 IME 对应的 FluentIMECore；准备方法同 `../search-geometry/REPORT.md`。`FLUENTKIT_MOTION_LIBRARY` 指定框架旧对象，`FLUENTIME_MOTION_SOURCE` 指定旧应用动画源文件。`before/` 保留首次探索；最终同一应用探针对照为 `baseline-final/`、`after/`。
