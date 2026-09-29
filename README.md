# Rnotes

我的 R 包开发笔记站点：<https://hui950319.github.io/Rnotes/>

每个包一个分区，记录函数设计、性能评估和使用经验。函数参考文档见各包自己的
pkgdown 站点；因果推断读书笔记另见 [causalR](https://hui950319.github.io/causalR/)。

## 本地渲染

```bash
quarto render
```

站点用 Quarto book 构建，输出到 `docs/`，GitHub Pages 从 `main` 分支的 `docs/` 发布。
含 R 代码块的页面由 `execute: freeze: auto` 缓存在 `_freeze/`，只有源文件变动时才重跑。

## 数据说明

仓库公开。笔记中的分析结果只含汇总统计量，不含任何个体水平数据；
`.gitignore` 默认拒绝常见数据格式，只放行 `*/bench/*.csv` 计时结果。
