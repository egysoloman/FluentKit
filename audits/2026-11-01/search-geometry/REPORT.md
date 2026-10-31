# SearchBox 聚焦文字偏移复核与修复

2026-11-01。对应 FOLLOW-UP 第 3 项。本批关闭可复现的聚焦文字左移；圆角/焦点线、候选浮层、页面动画、系统主题仍继续分批检查。

## 结论与归因

`FluentSearchTextField` 的未编辑文字由 `NSSearchFieldCell` 绘制，进入编辑后改由共享 field editor 绘制。实测原生 cell 的字形位于 `searchTextRect` 内侧 2pt；框架的单行编辑器配置却把 `lineFragmentPadding` 统一清零。因此 cell 的文字区域与 editor frame 即使一致，实际字形仍会在聚焦时左移 2pt。占位文字与已有文字均受影响。

修复在共享编辑会话配置处为搜索框恢复原生 2pt 内边距，其他文本控件保持现有配置。会话在同步及 AppKit 初始化后的延迟配置中都会应用，覆盖编辑器在不同控件间复用的情况。只改 cell 初始化会被后续共享配置覆盖。

| 检查 | 旧框架 | 修复后 |
| --- | --- | --- |
| 32 组字形比较的左边缘变化 | 全部 −2pt | 全部 0pt |
| 新像素回归测试，16 组合 × 两次编辑器复用 | 64 处断言失败 | 0 失败 |
| 实际 IME 标题栏光标 x（控件内） | 30pt | 32pt，与未编辑原生文字起点一致 |
| 实际 IME 7 状态的搜索控件身份 | 全部保留 | 全部保留 |
| marked text 期间缩至 600 / 放至 1000pt | 保留 | 保留 |

32 组比较覆盖深浅色、LTR/RTL、中英文、占位/已有文字、1×/2×。完整字形边界在修复后相差最多一个设备像素，这是原生 cell 直接绘制与 layer 光栅化的抗锯齿差异；左边缘在全部组合中完全一致。数据见 `glyph-comparison.json`。

## 独立复现与真实应用

- `baseline/`：修改前 `1b0186d` 的 Release 对象，SHA-256 `944145b0f8fba755321dc8788b661bd9a4ad4e909c83ab368a31f4b1a7d5af1f`。
- `after/`：修复后的相同探针、40 状态/80 张图。两个版本的对象哈希分别记录在各自目录。
- `before/tests.log`：同一最终测试在独立 `572628d` checkout 的失败输出；该版本与 `1b0186d` 的搜索编辑代码相同。`before/` 还保留最初仅取 layer 的实验数据，不能把其中未编辑文本缺失解释为实际显示缺陷。
- `settings-before/`、`settings-after/`：编译实际 `/Users/stars/Downloads/Fluent IME` 的设置窗口代码，使用同一份当前 FluentIMECore、临时 Rime 用户目录。输入“拼音”触发应用真实页面重建，随后模拟 marked text 并缩放窗口。两次应用源码哈希相同；没有修改或安装输入法。
- 通过电脑界面直接查看独立测试窗口：旧版在聚焦时左移 4 个屏幕像素（2×）；新版聚焦前后位置一致。活动中的已安装 IME 仍使用其原来静态链接的框架，不能因此声称它已经升级。

**渲染边界：** AppKit 的未编辑搜索 cell 内容在 `CALayer.render(in:)` 中可能缺失，但真实屏幕上存在。最终探针对未编辑状态直接调用原生 cell 绘制，活动 editor 使用 layer；每条记录含 `renderMode`。这些图用于文字几何，不能拿未编辑图判断背景或圆角。实际 IME 的整窗 layer 图也受同一限制，控件身份/光标/组合状态以记录的真实视图和 editor 数据为准。

## 验证

- 377 项测试通过；日志无 AppKit 约束诊断。
- 原生验证通过；Gallery Debug 构建通过；Release 输入/快照/编辑/材质/排版质量门禁通过。
- 原生验证旧断言曾要求光标紧贴 `searchTextRect.minX`，这正是错误的几何假设。保留失败日志 `after/native-validation-old-expectation.log`，将预期修正为原生内容内边距；独立像素回归验证真实字形，不以同一 frame 相等代替。
- 框架运行时代码只有 `FluentTextEditing.swift` 与 `FluentTextField.swift` 的配置改动。

## 复现

```sh
./audits/2026-11-01/search-geometry/run.sh /tmp/search-geometry-review
swift test --scratch-path /tmp/fluentkit-repair-tests --filter SearchTextAlignmentTests
python3 audits/2026-11-01/search-geometry/check_results.py
```

实际 IME 探针需要先构建与当前应用源码匹配的 Core：

```sh
swift build --package-path '/Users/stars/Downloads/Fluent IME' --target FluentIMECore \
  -c release --scratch-path /tmp/fluentkit-ime-search-audit
./audits/2026-11-01/search-geometry/run-settings.sh /tmp/ime-search-review
```

`FLUENTKIT_SEARCH_LIBRARY` 可指定已保存的旧 Release 对象；`FLUENTIME_SOURCE` / `FLUENTIME_BUILD` 可覆盖应用源码/Core 路径。旧对象不纳入 Git，以保存的哈希及基线提交识别。

## 仍未关闭

WinUI 字体/字形的跨平台像素对拍、搜索圆角和四种交互状态、实际中文输入法候选窗与 VoiceOver 均不由本批测试代替。`setMarkedText` 只验证编辑器状态保持，不能证明物理输入、候选定位和选词已经通过。
