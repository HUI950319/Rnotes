# Figures for the Rnotes page "MLR: get_vpd / get_ale / get_ale2 提速策略与实测".
# Run in Windows R (needs ggplot2, ragg and the Microsoft YaHei font) from the
# folder that holds the mlr_vpd_20261006_*.csv files.
suppressMessages(library(ggplot2))
fam <- "Microsoft YaHei"
model_lab <- c(sur_cox = "Cox（生存）", sur_rf = "随机生存森林", sur_xgb = "XGBoost（生存）",
               log_glm = "Logistic（二分类）", log_rf = "随机森林（二分类）",
               log_xgb = "XGBoost（二分类）")
call_lvl <- c("get_exp()", "get_vpd(Age)", "get_vpd(T_stage)", "get_vpd(Sex, Age)",
              "get_ale(Age)", "get_ale(T_stage)", "get_ale(Sex, Age)",
              "get_ale2(Age, Tum)", "get_ale2(Sex, Age)")
tim <- read.csv("mlr_vpd_20261006_timing.csv", encoding = "UTF-8")
tim$model <- factor(model_lab[tim$model], levels = model_lab)
tim$call  <- factor(tim$call, levels = rev(call_lvl))
tim$version <- factor(tim$version, levels = c("优化前（78e5ec5）", "优化后（d67b1ae）"))
th <- theme_bw(base_size = 11, base_family = fam) +
  theme(legend.position = "top", panel.grid.minor = element_blank(),
        strip.background = element_rect(fill = "grey92"))
save2 <- function(p, stem, w, h) {
  ragg::agg_png(paste0(stem, ".png"), width = w, height = h, units = "in", res = 150)
  print(p); grDevices::dev.off()
  grDevices::cairo_pdf(paste0(stem, ".pdf"), width = w, height = h, family = fam)
  print(p); grDevices::dev.off()
}

# 1. 5 万行：优化前后，每种模型 9 个调用
d50 <- subset(tim, n == 50000)
p1 <- ggplot(d50, aes(compute_s, call)) +
  geom_line(aes(group = call), colour = "grey65", linewidth = 0.6) +
  geom_point(aes(colour = version), size = 2.3) +
  scale_x_log10(breaks = c(0.1, 0.3, 1, 3, 10, 30),
                labels = c("0.1", "0.3", "1", "3", "10", "30")) +
  scale_colour_manual(values = c("grey55", "#C0392B")) +
  facet_wrap(~ model, ncol = 3) +
  labs(x = "计算耗时（秒，对数刻度；不含画图）", y = NULL, colour = NULL,
       title = "5 万行：优化前后的计算耗时") + th
save2(p1, "mlr_vpd_20261006_before_after_50k", 11, 7.2)

# 2. 每项提交的代表性提速（各自的数据和调用不同，只看倍数）
cm <- read.csv("mlr_vpd_20261006_commits.csv", encoding = "UTF-8")
cm$speedup <- cm$before_s / cm$after_s
fmt <- function(x) ifelse(x >= 100, sprintf("%.0f", x), ifelse(x >= 1, sprintf("%.1f", x), sprintf("%.2f", x)))
cm$label <- sprintf("%s → %s s（%.1f 倍）", fmt(cm$before_s), fmt(cm$after_s), cm$speedup)
cm$y <- factor(paste0(cm$commit, "  ", cm$strategy), levels = rev(paste0(cm$commit, "  ", cm$strategy)))
cm$category <- factor(cm$category, levels = c("预测器", "并行", "减少计算量", "建模"))
p2 <- ggplot(cm, aes(speedup, y, fill = category)) +
  geom_col(width = 0.68) +
  geom_text(aes(label = label), hjust = -0.04, family = fam, size = 3.1) +
  scale_x_log10(breaks = c(1, 2, 5, 10, 20, 50), expand = expansion(mult = c(0, 0.75))) +
  scale_fill_manual(values = c("#2E86C1", "#28B463", "#D68910", "#8E44AD")) +
  labs(x = "提速倍数（优化前 / 优化后，对数刻度）", y = NULL, fill = NULL,
       title = "16 项优化各自的代表性实测") + th
save2(p2, "mlr_vpd_20261006_commits", 11, 6.6)

# 3. 优化后：1 万 / 5 万 / 10 万行的计算耗时
da <- subset(tim, version == "优化后（d67b1ae）")
da$n_lab <- factor(sprintf("%s 万行", da$n / 1e4), levels = c("1 万行", "5 万行", "10 万行"))
da$lab <- ifelse(da$compute_s >= 10, sprintf("%.0f", da$compute_s), sprintf("%.1f", da$compute_s))
p3 <- ggplot(da, aes(model, call, fill = compute_s)) +
  geom_tile(colour = "white") +
  geom_text(aes(label = lab), family = fam, size = 3) +
  scale_fill_gradient(low = "#FDFEFE", high = "#E74C3C", trans = "log10",
                      breaks = c(0.1, 1, 10), labels = c("0.1", "1", "10")) +
  facet_wrap(~ n_lab, ncol = 3) +
  labs(x = NULL, y = NULL, fill = "秒", title = "优化后：各样本量的计算耗时（秒）") +
  th + theme(axis.text.x = element_text(angle = 35, hjust = 1))
save2(p3, "mlr_vpd_20261006_after_by_n", 12, 5.6)
cat("figures done\n")
