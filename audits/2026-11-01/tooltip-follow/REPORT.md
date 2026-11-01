# 可选 Tooltip 连续过渡

本批独立实现用户动图中的跨目标移动、宽度变化、内容淡化。作者尚未公开源码，没有移植第三方代码，也不把参考行为称为 WinUI 原生行为。配色不在本批模仿范围。

## 参考及实现

用户 GIF 为 140 帧、7,410 ms；文件哈希见 `reference-sha256.txt`。逐帧观察支持：第一次有悬停等待；跨标题栏按钮时浮层连续移动并改变宽度；同一按钮内大体保留进入时的位置。最后一点是依据画面的推断，不是作者公布的算法。

新增 `.toolTip("Help", placement: .bottom, motion: .continuous)`，默认仍为 `.standard`。连续模式在同一窗口内转交同一个 panel 与材质表面；从当前几何位置重新定向，独立捕获、淡化内容，避免复制或栅格化材质本身。第一目标维持既有等待，跨目标立即转交。几何过渡 220 ms、显示/隐藏淡化 180 ms、离开安全区域缓冲 120 ms 是本实现的参数，不是 WinUI 标准数值。

Windows 样式最小化、最大化/还原、关闭按钮使用该模式，保留 NSButton 的原生窗口动作和辅助功能标签，关闭重复的系统 `toolTip`。补充 Gallery 对照行、README 与 CHANGELOG。没有修改或安装 Fluent IME。

## 生命周期与独立检查

- 打断移动从当前帧继续，快速淡出后转交不会被旧关闭回调误关。
- 首次延迟被取消、跨窗口、默认模式、长文本、屏幕边缘、RTL、降低动态效果，以及中途启用降低动态效果分别检查。
- 窗口移动、缩放、关闭、最小化、失去活动状态和真实移除清理浮层；鼠标按下或滚动关闭提示，不吞掉事件。没有合成 scrollWheel。
- 实测 AppKit 在改变原生 titlebar accessory 外观时会同步经历 `window=nil` 再挂回同一窗口。连续模式允许这一轮主线程内的重挂载；真实移除下一轮关闭，换窗口立即关闭。新增主题切换检查复现并守护此路径。
- 窗口已隐藏时，延迟任务不能再打开浮层。标题栏包装后的动作路由与最大化/还原标签有独立检查。

## 证据与验证

`TooltipMotionAudit.swift` 建立独立原生窗口，采样真实 panel 的位置、大小、透明度、内容透明度和 windowNumber；直接渲染自身 layer tree 保存图片。`check-native.py` 检查中间帧、打断返回、唯一 panel、主题切换和退出。图片是诊断窗口的渲染，不代表桌面合成器的完整阴影或真实鼠标延迟。

第一轮 `native-first/`：47 个时间样本，41 个显示样本，始终只有 1 个 panel 实例；包含中间位移、宽度收缩、文字淡化及离开后的完整关闭。保留原始数据。

早期 `targeted-tests.log` 和 `full-tests.log` 保留了 titlebar accessory 主题重挂载导致提示关闭的失败。`targeted-final.log` 为修复后的 12 项检查通过。`full-tests-final.log` 是新增动作测试的字段名与 NSWindow 属性冲突产生的编译失败，不属于运行时回归；字段已更名。最终结果见下表。

## 边界

此批验证不替代 Windows 像素对拍、真实 VoiceOver、物理鼠标延迟测量或多显示器实机验收。通用可选透明材质属于下一批：现有 `FluentMaterialSurface` 已可包装内容，但其材质/圆角配置更新被冻结；Tooltip 仍固定 Acrylic；容器与窗口需要明确的采样范围和辅助功能回退。保留这些发现，不能以本批动效通过宣称材质工作完成。

## 最终检查

| 检查 | 结果 | 证据 |
|---|---|---|
| 全套 XCTest | 461 通过，0 失败 | `full-tests-final2.log` |
| 原生动作/布局验证 | PASS | `native-validation.log` |
| Gallery Debug 构建 | BUILD SUCCEEDED | `gallery-build-final2.log` |
| Release 质量门禁 | PASS | `quality-run.log`、`quality/` |
| 原生动效采样 | 47 帧，1 个 panel，全部检查通过 | `native-final/samples.json`、`verification.json`、6 张 PNG |

本轮 CUA 原生接口未提供 hover/mouse-move 操作，因此没有声称重演真实鼠标悬停；原生 fixture 自行调用宿主的输入处理并采样窗口。动态渲染和中间帧已经检查，物理鼠标、桌面合成阴影、多显示器路径继续单独验收。未改变用户全局外观/输入设置。
