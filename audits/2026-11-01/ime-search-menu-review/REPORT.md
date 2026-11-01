# IME 搜索框提示语与编辑菜单：最新版复核

用户三张截图对应搜索框右键菜单，以及聚焦/失焦时的“查找设置”。本批在 `9e8acd99ec47321e301e1e9c58239d30bc22c053` 的 Release 框架上独立复测，没有更换运行中的输入法。**结论：菜单已有快速淡入，但默认透明材质及 IME 字体偏上没有自动解决。**

## 搜索文字

使用应用 `IMEChrome.swift` 中相同的 fontProvider：优先 `MicrosoftYaHei`，否则系统字体。原生搜索框固定 310×32pt，对比框架默认字体和该 provider；深浅色、LTR/RTL、中英文、占位/聚焦/输入/组合/失焦共 80 状态、160 张 1×/2× 图。

对深色 LTR 中文的 2× 实际字形采样（像素边界按半开区间计算）：

| 字体 | 提示语失焦 / 聚焦中心 y | 已输入文字失焦 / 聚焦中心 y | 控件中心 |
| --- | --- | --- | --- |
| 框架默认系统字体 | 16 / 16pt | 16 / 16pt | 16pt |
| IME 的 MicrosoftYaHei | 14 / 14pt | 14 / 14pt | 16pt |

因此用户看到的偏上可复现，约 **2pt（2× 下 4px）**，且不只占位文字。之前修复的焦点切换水平位移没有复发；“焦点前后位置一致”不能证明自定义字体的视觉中心正确。后续修复应核对自定义字体的行框与基线，不能给所有默认搜索框统一下移 2pt。

原始数据 `current/results.json`、`current/images/`、`vertical-ink.json`。继承前次正确的绘制策略：未编辑时直接画 native cell，编辑时取 layer。前者只用于字形几何，不用于评价背景圆角；像素采样不把 caret 计入字形。

## 菜单动画与材质

搜索编辑菜单使用 `FluentTextCommandFlyout`，不是 `FluentMenuFlyout`。直接对自己的原生搜索框发送右键事件，并采样真实 presentation layer：

- 默认菜单透明度在 20ms 为 0.184、53ms 为 0.580、87ms 为 0.986，104ms 到 1；注册动画 duration 为 **0.083 秒**。这证明新版确有淡入，速度较快。
- WinUI 本地参考 `src/controls/dev/CommandBarFlyout/CommandBarFlyout_themeresources.xaml:654–661` 的 OpeningOpacityStoryboard 也使用 ControlFasterAnimationDuration。不能据普通菜单或跟随 tooltip 的效果，直接把这里改成较长缩放动画。
- 默认 `.acrylic` 实测 backend 为 **fluentRecipe**，当前实现绘制固定底色，没有真实背景模糊。显式配置 `.nativeAcrylic` 得到 visualEffect，`.liquidGlass` 得到 nativeGlass；关闭材质得到 opaque。四条路径均保留 editor，淡入也均存在。
- 应用的 `Preferences.advancedEffects` 用于候选栏、模式指示器、Emoji 等；`Preferences.theme` 没有为编辑菜单的 `.transient` 材质建立相应配置。因此开关不会自动把这类菜单切到原生透明效果。另测得 panel.hasShadow=false；完整阴影与关闭动画仍需另验。

原始 4 组、每组 32 帧记录见 `menu.json`。当次系统 Reduce Motion / Reduce Transparency 均为 false，没有修改系统偏好。材质后端检查证明选择路径，不等同于桌面模糊质量或跨屏效果验收。

## 版本边界和下一步

`v0.2.0..9e8acd9` 中搜索文字几何及编辑会话源文件没有变化；TextCommandFlyout 的变化为选屏通知，并未改变上述字体或默认材质。已安装 IME 的 plist 为 0.5.2 / build 16，但未记录静态链接的 FluentKit SHA，不能仅凭应用版本推断其框架版本。

这次只复核和保留证据，未把两项列为已修：

1. 校准 IME 自定义字体的行框/基线，同时验证提示、实字、caret、字号缩放和组合输入；保护默认字体已正确的几何。
2. 在应用中把高级效果开关接到 transient 角色材质，保留框架默认预设及开发者覆盖能力，另验 Reduce Transparency 和显式主题。

重现字形：`zsh run-geometry.sh <新输出目录>`；`zsh run-menu.sh <Swift Build Release products目录> <新输出目录>` 可复测编辑菜单；`python3 check_review.py` 校验本批原始结果。框架对象哈希保存在 `current/library-sha256.txt`。
