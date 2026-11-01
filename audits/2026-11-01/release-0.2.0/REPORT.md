# FluentKit 0.2.0 发布候选验证

用户已明确授权推送 GitHub 并发布 Release。遵循 RELEASING.md：版本/安装示例/CHANGELOG 一致，本地门禁通过后推 main，等待该提交的 CI 成功，再创建 annotated tag 并发布 latest Release。运行时最后修改为 `4fc002b`；剩余提交仅为版本与审计文档。

## 本地门禁

- Debug build：通过（`debug-build.log`）。
- XCTest：489 项，0 失败（`tests.log`）。约束诊断扫描：none（`constraint-diagnostics.log`），此前 Refresh 告警已独立修复。
- 交互桌面原生验证：PASS（`native-validation.log`）。
- 所有产品 Release build：通过，115.19 秒（`release-build.log`）。
- Xcode Gallery：BUILD SUCCEEDED（`gallery-build.log`）。
- Release 工作计数/身份/外部重置/字体/材质与样例门禁：通过（`quality-run.log`、`quality/`）。
- Refresh 独立原生断点探针：已解析、0 命中、正常退出（`../refresh-initial-layout/after/`）。

## 视觉检查范围

重新生成并查看 980×680 的 Controls Light/Dark 和 Accessibility RTL 三张 Gallery 图像，并逐张查看同名 `.snapshots/` 历史图作对照。当前标题字号、图标和固定材质配方较历史图变化，滚动条样式也不同；已确认所选状态未出现空白页面、错侧的 RTL 导航或正文/Expander 相互重叠。候选图片在本目录，历史基线保持原样，不把这些有意差异称为像素比对通过。Release 样例门禁另包含 Light/Dark/RTL 挂载；质量工具生成的交互状态图像见 `quality/visual/`。

这不是 Windows 对拍，也不是所有控件的动态/实机验收。已知 Toggle 键盘提交时机、窄窗设置卡描述、多显示器及真实输入/辅助功能任务仍在 FOLLOW-UP；Release notes 明确保留这些限制。

`RELEASE-NOTES.md` 是要发布的正文。远端 CI 与 Release 的结果以该提交对应的 GitHub 运行和标签为准，不用本地通过替代远端门禁。
