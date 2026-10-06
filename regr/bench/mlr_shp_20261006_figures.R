# Figures for the Rnotes page "MLR：get_shp 提速策略与实测".
# Run in Windows R (needs ggplot2, ragg and the Microsoft YaHei font) from the
# folder that holds the mlr_shp_20261006_*.csv files.
suppressMessages(library(ggplot2))
fam <- "Microsoft YaHei"
th <- theme_bw(base_size = 11, base_family = fam) +
  theme(legend.position = "top", panel.grid.minor = element_blank(),
        strip.background = element_rect(fill = "grey92"))
save2 <- function(p, stem, w, h) {
  ragg::agg_png(paste0(stem, ".png"), width = w, height = h, units = "in", res = 150)
  print(p); grDevices::dev.off()
  grDevices::cairo_pdf(paste0(stem, ".pdf"), width = w, height = h, family = fam)
  print(p); grDevices::dev.off()
}

# 1. 优化前后：每个场景的中位耗时
tim <- read.csv("mlr_shp_20261006_timing.csv", encoding = "UTF-8")
med <- aggregate(seconds ~ platform + scenario + label + version, tim, median)
med$version <- factor(med$version, levels = c("优化前（df0486b）", "优化后（0d3247c）"))
lvl <- unique(tim$label)
lvl <- c(lvl[!grepl("^会话首次调用", lvl)], lvl[grepl("^会话首次调用", lvl)])
med$label <- factor(med$label, levels = rev(lvl))
med$platform <- factor(med$platform, levels = unique(tim$platform))
p1 <- ggplot(med, aes(seconds, label)) +
  geom_line(aes(group = label), colour = "grey65", linewidth = 0.6) +
  geom_point(aes(colour = version), size = 2.4) +
  scale_x_log10(breaks = c(0.3, 1, 3, 10, 30, 100),
                labels = c("0.3", "1", "3", "10", "30", "100")) +
  scale_colour_manual(values = c("grey55", "#C0392B")) +
  facet_wrap(~ platform, ncol = 2, scales = "free_y") +
  labs(x = "耗时（秒，对数刻度；1 万行训练、解释 400 行、带交互）", y = NULL,
       colour = NULL, title = "get_shp() 优化前后的耗时") + th
save2(p1, "mlr_shp_20261006_before_after", 11, 5.6)

# 2. 每项提交的代表性实测（各自的场景不同，只看倍数）
cm <- read.csv("mlr_shp_20261006_commits.csv", encoding = "UTF-8")
cm$speedup <- cm$before_s / cm$after_s
fmt <- function(x) ifelse(x >= 10, sprintf("%.0f", x), sprintf("%.1f", x))
cm$label <- sprintf("%s → %s s（%.1f 倍）", fmt(cm$before_s), fmt(cm$after_s), cm$speedup)
cm$y <- factor(paste0(cm$commit, "  ", cm$strategy, "\n", cm$measurement),
               levels = rev(paste0(cm$commit, "  ", cm$strategy, "\n", cm$measurement)))
cm$category <- factor(cm$category, levels = c("建模", "SHAP 准备", "SHAP 计算", "加载"))
p2 <- ggplot(cm, aes(speedup, y, fill = category)) +
  geom_col(width = 0.68) +
  geom_text(aes(label = label), hjust = -0.04, family = fam, size = 3.1) +
  scale_x_log10(breaks = c(1, 2, 5, 10), expand = expansion(mult = c(0, 0.6))) +
  scale_fill_manual(values = c("#2E86C1", "#28B463", "#D68910", "#8E44AD")) +
  labs(x = "提速倍数（优化前 / 优化后，对数刻度）", y = NULL, fill = NULL,
       title = "各项优化的代表性实测") + th +
  theme(axis.text.y = element_text(size = 8.5, lineheight = 0.9))
save2(p2, "mlr_shp_20261006_commits", 11, 6.4)

# 3. 连续变量分箱：训练耗时与 SHAP 一致性
bn <- read.csv("mlr_shp_20261006_binning.csv", encoding = "UTF-8")
bn <- subset(bn, !grepl("参照", treatment))
bn$distinct <- pmax(bn$age_distinct, bn$tum_distinct)
bn$kind <- ifelse(grepl("分箱", bn$treatment), "分位数分箱",
                  ifelse(grepl("取整", bn$treatment), "取整", "不处理"))
bn$tag <- ifelse(bn$kind == "不处理", "不处理（连续值）",
                 sub("分位数分箱 ", "", bn$treatment))
d1 <- data.frame(distinct = bn$distinct, value = bn$train_s, kind = bn$kind,
                 tag = bn$tag, panel = "训练耗时（秒，对数刻度）")
d2 <- data.frame(distinct = bn$distinct, value = bn$row_shap_cor, kind = bn$kind,
                 tag = bn$tag, panel = "与不分箱模型的逐行 SHAP 相关")
d2 <- d2[!is.na(d2$value), ]
# Labels: bins above the line, rounding below it, the unbinned point to its left.
d1$vj <- ifelse(d1$kind == "取整", 1.9, ifelse(d1$kind == "不处理", 0.5, -0.9))
d1$hj <- ifelse(d1$kind == "不处理", 1.1, 0.5)
d2$vj <- ifelse(d2$kind == "取整", -0.9, 1.9)
d2$hj <- ifelse(d2$distinct >= 1000, 0.8, 0.5)
p3a <- ggplot(d1, aes(distinct, value)) +
  geom_line(data = subset(d1, kind == "分位数分箱"), colour = "grey60") +
  geom_point(aes(colour = kind), size = 2.4) +
  geom_text(aes(label = tag, vjust = vj, hjust = hj), family = fam, size = 3) +
  scale_x_log10() + scale_y_log10(expand = expansion(mult = c(0.12, 0.08))) +
  scale_colour_manual(values = c(不处理 = "grey40", 分位数分箱 = "#C0392B", 取整 = "#2E86C1")) +
  labs(x = "每个连续变量的不同取值数（对数刻度）", y = "训练耗时（秒）", colour = NULL,
       title = "训练耗时") + th
p3b <- ggplot(d2, aes(distinct, value)) +
  geom_hline(yintercept = 0.997, linetype = "dashed", colour = "grey45") +
  annotate("text", x = 60, y = 0.9975, label = "同一分箱换随机种子：0.997",
           hjust = 0, vjust = -0.4, family = fam, size = 3, colour = "grey30") +
  geom_line(data = subset(d2, kind == "分位数分箱"), colour = "grey60") +
  geom_point(aes(colour = kind), size = 2.4) +
  geom_text(aes(label = tag, vjust = vj, hjust = hj), family = fam, size = 3) +
  scale_x_log10(expand = expansion(mult = c(0.08, 0.08))) +
  scale_colour_manual(values = c(分位数分箱 = "#C0392B", 取整 = "#2E86C1")) +
  coord_cartesian(ylim = c(0.985, 1)) +
  labs(x = "每个连续变量的不同取值数（对数刻度）", y = "逐行 SHAP 相关", colour = NULL,
       title = "与不分箱模型的一致性") + th
ragg::agg_png("mlr_shp_20261006_binning.png", width = 11, height = 4.6, units = "in", res = 150)
gridExtra::grid.arrange(p3a, p3b, ncol = 2); grDevices::dev.off()
grDevices::cairo_pdf("mlr_shp_20261006_binning.pdf", width = 11, height = 4.6, family = fam)
gridExtra::grid.arrange(p3a, p3b, ncol = 2); grDevices::dev.off()
