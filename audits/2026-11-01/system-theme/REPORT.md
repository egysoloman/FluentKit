# 系统主题漏更新：IME 与已有 ComboBox 浮层

2026-11-01。框架基线 `a330da0`。本批独立复现应用与框架两条路径，没有改变整机配色或替换正在运行的输入法。

## 确认的根因

1. IME SettingsWindow 比较的是 `Preferences.shared.theme` 的原始配置。系统从浅色切到深色时，配置仍为 `.system`，原有相等判断跳过刷新；窗口又显式固定了上次解析的 `appearance`，因此持续显示旧颜色。
2. 已经打开的 CandidateView、CandidateShadowView 和 EmojiPanel 没有完整订阅主题变化，要等下一次内容更新/打开才重新取色。
3. FluentComboBoxHost 更新主题时，只更新按钮，没有把新主题传给已有的 ComboBox 浮层。窗口安装 AppearanceCoordinator 时，浮层自己的订阅能补上；IME 直接嵌入 AppKit 的路径没有该协调器，因此遗漏。新增测试在旧代码上明确出现 Aqua 与 DarkAqua 不符，见 `before/combo-test.log`。

原生 TextField/Search/Secure 在本机的默认 system 模式能够响应原生外观变化，未因怀疑而给它们添加额外刷新钩子。

## 修复

- IME 新增 `IMEThemeObservation`，分别观察应用实际外观及偏好变化，比较**解析后的主题**。系统颜色变化不会伪造偏好通知或重新应用 Rime 输入选项。
- 设置页原地更新现有文字、控件、背景和面包屑，不为颜色变化重建页面。第一次尝试中发现重建会让试输入栏丢失焦点，已改掉；该中间失败保留在 `preview-rebuild/`，不是原始用户版本的新发现。
- 候选条、阴影及符号面板同步更新已存在的视图，保留选项实例、符号查询与页状态。
- 框架 ComboBox 将宿主主题传给已有浮层，并结束覆盖旧颜色的临时过渡层；不用关闭重开菜单。

IME 源码位于 `/Users/stars/Downloads/Fluent IME`，无 git。四个既有文件和一个新 helper 的修改保存为 `IME-system-theme.patch`，反向 dry-run 通过。改前完整文件哈希在 `before/app-source-sha256.txt`，改后在 `after/changed-source-sha256.txt` 与各 `final-*/app-source-sha256.txt`。没有安装构建产物，也没有修改用户输入法偏好。

## 结果与边界

| 验证 | 结果 |
| --- | --- |
| 实际 IME 源码，system/light/dark 三种应用选择 | 63 个状态通过：General 已打开菜单、搜索组合文字、试输入组合文字、候选和符号面板 |
| 浅→深→浅时已有菜单 | 同一浮层持续显示，选择不变；system 跟随，显式 light/dark 保持应用选择 |
| 编辑状态 | 搜索编辑器/试输入视图身份、组合文字和焦点保留；试输入文字不变 |
| 候选/符号面板 | 同一批选项实例；面板仍显示，`smile` 查询不变 |
| 实际 GalleryScreen 与 App 同样的协调器接线 | TextBox、Expander、ToggleSwitch、AutoSuggestBox、CommandBar、MenuBar、SplitButton 共 21 个状态通过；标题、背景、主题 store 和抽查控件一致 |
| 自动比较 | `checks.json`：84 个状态、492 项条件检查、0 错误 |
| 构建与门禁 | 385 项测试、原生验证、Gallery Debug、Release 质量门禁、实际 IME Release 产品构建全部通过；无 AppKit 约束诊断 |

原始失败在 `before/`。`after/`、`after-preview/`、`after-general/` 为阶段结果；最终结果是 `final-general/`、`final-search/`、`final-preview/` 和 `gallery/`。`preview-initial/` 的探针因搜索事件跳回首页，未正确建立试输入焦点，不能当作预览编辑回归证据；纠正后的结果单独保存，未覆盖旧数据。

探针只修改自身进程的 `NSApp.appearance`，验证原生外观信号之后的解析和传播链；没有用全局系统设置自动切换验收整机事件。搜索采用 AppKit marked text，试输入采用设置页自身的 Rime 路径；不等同于真实 IMK 跨进程输入验收。用户已确认录屏顶部蓝色候选条来自 macOS 自带拼音，其客户端锚点路径与 Fluent IME 自绘面板分别跟踪，见 `../candidate-popup/REPORT.md`。本批不关闭包装层旧内容捕获、VoiceOver、真实触摸或 Windows 像素对照。源码修复不会自动更新已安装且正在运行的静态链接输入法。

## 复现

```sh
THEME_AUDIT_EDIT_SEARCH=0 zsh audits/2026-11-01/system-theme/run-settings.sh /tmp/theme-review/final-general
zsh audits/2026-11-01/system-theme/run-settings.sh /tmp/theme-review/final-search
FLUENTIME_THEME_PAGE=preview zsh audits/2026-11-01/system-theme/run-settings.sh /tmp/theme-review/final-preview
zsh audits/2026-11-01/system-theme/run-gallery.sh /tmp/theme-review/gallery
python3 audits/2026-11-01/system-theme/check_results.py /tmp/theme-review
swift test --scratch-path /tmp/fluentkit-repair-tests --filter ThemePropagationRegressionTests
```

需要先构建脚本指定的 FluentKit/FluentIMECore Release 产物和应用现有 Rime 资源。每个应用探针使用独立临时 Rime 用户目录；窗口图片直接渲染 layer tree。
