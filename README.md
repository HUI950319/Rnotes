# Rnotes

我的 R 包开发笔记站点：<https://hui950319.github.io/Rnotes/>

每个包一个分区，记录函数设计、性能评估和使用经验。函数参考文档见各包自己的
pkgdown 站点；因果推断读书笔记另见 [causalR](https://hui950319.github.io/causalR/)。

侧栏在 `_quarto.yml` 中用 `href` 与 `text` 分别设置页面路径和导航短标题，文章保留完整标题。
RegR、MLR、UtilsR、causalR 按主题使用嵌套 `part` 分组；其余四个包保留两级目录。
分组时保持章节顺序，以免改变正文图号；当前页面的祖先目录自动展开。
侧栏分组支持鼠标点击，以及 Tab 聚焦后用 Enter 或空格展开、折叠。

## 更新与代码约定

- 函数改动后原地修改教程中对应的小节；需要单独成节的新内容放在相关函数的小节下，标题末尾括注日期，不在页面顶部追加“当前…”节。
- 每页末尾的“更新记录”是折叠框，每条一句话；首页“近期更新”只保留最近 10 条，完整记录和接口入口见[更新记录](https://hui950319.github.io/Rnotes/updates.html)。
- 版本快照、执行环境与改名说明放在页首折叠的“版本与复现记录”中。
- 正文代码只放读者要运行的调用；`stopifnot()` 等复核代码放在紧随其后的折叠框“复核代码”里。

## 本地渲染

```bash
python -m pip install beautifulsoup4 PyYAML Pillow
quarto render
```

站点用 Quarto book 构建，输出到 `docs/`，GitHub Pages 从 `main` 分支的 `docs/` 发布。
含 R 代码块的页面由 `execute: freeze: auto` 缓存在 `_freeze/`，只有源文件变动时才重跑。
渲染后自动运行 `scripts/prepare_images.py`：正文图片使用懒加载、异步解码和原始宽高，
PNG 同时提供更小的无损 WebP 预览。预览逐像素核验；原 PNG 与放大链接继续保留。
已有预览按原 PNG 的内容哈希复用，无需重新编码。也可单独运行该脚本更新已生成页面。
首页“笔记目录”不手工维护：渲染前 `scripts/build_directory.py` 按 `_quarto.yml` 的章节顺序，
从每页 front matter 的 `directory`（`title`、`topic`、`updated`，必要时 `package`）生成 `_note-directory.md`，
`index.qmd` 引入该文件。不进目录的章节写 `directory: false`；两者都没有时渲染会报错，避免新页漏登。
`scripts/prepare_directory.py` 随后从搜索索引提取各页的函数名，补充首页目录的筛选关键词。
新增教程或更新函数后，正常渲染即可同步；也可单独运行该脚本更新已有目录。
窄屏下正文行内代码允许换行；多行代码块和宽表继续在各自区域内横向滚动。
教程里粘贴的大段渲染结果（```` ```{=html} ```` 表格）放在 `<包>/_html/<页名>/NN.md`，正文在原位置用
`{{< include _html/<页名>/NN.md >}}` 引入；下划线目录不会被单独渲染，展开后与直接写在正文里的输出逐字节相同。
新增或重新生成 iframe 交互图（自包含的 htmlwidget 页面）后运行 `python scripts/share_widget_libs.py`：
多页重复内联的 plotly.js、jQuery 等脚本移到 `assets/widget-libs/` 共用，源文件与 `docs/` 副本同步改写。

发布前检查已生成的站点（不重跑模型分析；R 检查只解析代码并执行小型基础示例）：

```bash
python -m pip install beautifulsoup4==4.14.3 PyYAML==6.0.3 playwright==1.63.0
python -m playwright install --with-deps chromium --only-shell
python scripts/check_site.py
python scripts/check_source_links.py
Rscript scripts/check_examples.R
python scripts/check_browser.py
```

不想在系统 Python 里安装 Playwright 时，可用 [uv](https://docs.astral.sh/uv/) 在临时环境中运行浏览器检查
（Chromium 仍需按上面第二行安装一次）：

```bash
uv run --no-project --with playwright==1.63.0 --with beautifulsoup4==4.14.3 --with PyYAML==6.0.3 python scripts/check_browser.py
```

检查页底与 HTML 头部的上一页／下一页是否遵循 `_quarto.yml`，以及侧栏层级、短标题、当前页展开状态、面包屑、
站内链接与锚点、页面摘要、图片替代文本与懒加载、全站图号唯一性、MLR 总览图数、搜索索引和 sitemap。
R 检查解析教程代码，并实际验证 SHAP 分箱边界、分层示例数据构造与 RPA 时间换算。
装有当前 UtilsR、ggplot2、patchwork 的环境可再运行 `Rscript scripts/check_examples.R --runtime`，
直接执行本站命名轴 Sankey、受试者 ID 配对检验与命名 list 展平示例，并检查图形构建和统计结果。
配对 P 值与独立的完整配对 t 检验核对；这些检查不拟合临床模型、不写入用户包库。
CI 保留前面的基础检查；当前开发源码的 runtime 检查在本机完成。
源码链接检查通过 GitHub CLI 的只读 HEAD 请求，核对各包源文件、目录与提交快照；
Windows 使用已认证的 WSL Ubuntu-22.04 gh，其他平台使用本机 gh，CI 使用只读 GitHub token。
不存在的分支、文件或未推送提交返回非零状态；源码链接固定到运行快照时，不会要求跟随最新 HEAD。
RegR、MLR 和 seerR 为私有仓库，本机授权账号检查全部目标。Rnotes 的 CI token 无法读取这些库时，
明确报告跳过的私有目标，继续检查其余可访问目标；不把权限导致的 404 当成失效文件。
Chromium 检查 67 个代表页面在桌面及手机宽度下的溢出、亮色／暗色切换、标签页显示、
首页筛选与 JavaScript 错误；只访问本地 `docs/`，使用备用字体。R 需 4.4.3；各检查失败均返回非零状态。
GitHub Actions 会在每次 push 和 pull request 中执行这四项检查。

## 数据说明

仓库公开。笔记中的分析结果只含汇总统计量，不含任何个体水平数据；
`.gitignore` 默认拒绝常见数据格式，只放行 `*/bench/*.csv` 计时结果。
