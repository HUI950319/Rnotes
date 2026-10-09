# Rnotes

我的 R 包开发笔记站点：<https://hui950319.github.io/Rnotes/>

每个包一个分区，记录函数设计、性能评估和使用经验。函数参考文档见各包自己的
pkgdown 站点；因果推断读书笔记另见 [causalR](https://hui950319.github.io/causalR/)。

侧栏在 `_quarto.yml` 中用 `href` 与 `text` 分别设置页面路径和导航短标题，文章保留完整标题。
RegR、MLR、UtilsR、causalR 按主题使用嵌套 `part` 分组；其余四个包保留两级目录。
分组时保持章节顺序，以免改变正文图号；当前页面的祖先目录自动展开。
侧栏分组支持鼠标点击，以及 Tab 聚焦后用 Enter 或空格展开、折叠。

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
`scripts/prepare_directory.py` 随后从搜索索引提取各页的函数名，补充首页目录的筛选关键词。
新增教程或更新函数后，正常渲染即可同步；也可单独运行该脚本更新已有目录。
窄屏下正文行内代码允许换行；多行代码块和宽表继续在各自区域内横向滚动。

发布前检查已生成的站点（不执行 R 分析）：

```bash
python -m pip install beautifulsoup4 PyYAML
python scripts/check_site.py
```

检查页底与 HTML 头部的上一页／下一页是否遵循 `_quarto.yml`，以及侧栏层级、短标题、当前页展开状态、面包屑、
站内链接与锚点、页面摘要、图片替代文本与懒加载、全站图号唯一性、搜索索引和 sitemap。
GitHub Actions 会在每次 push 和 pull request 中执行同一检查。

## 数据说明

仓库公开。笔记中的分析结果只含汇总统计量，不含任何个体水平数据；
`.gitignore` 默认拒绝常见数据格式，只放行 `*/bench/*.csv` 计时结果。
