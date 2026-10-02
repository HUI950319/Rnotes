# RPA 生存路径：方案 A（只算参照组对比）与方案 B（最多 50 个时间点）的前后对比
#
# 以下是实际运行过的独立脚本，按运行顺序原样收录；每段单独存成 .R，在 Windows R 的
# Rscript 下运行。base_rpa.rds 由 rpa_cox_bench.R 第 0 部分生成；base2.rds 由第 3 段
# 自己生成（多保留 event / status 两列，供竞争风险使用）。
# "before" / "after" 指先后安装的两个 RegR 版本：
#   第 1 段 before = A 之前，after = 63541f6（A，Cox）
#   第 3 段 before = 63541f6，after = c71fe16（B）
#   第 5 段 before = c71fe16，after = c1f6435（A，CSC）；脚本即第 3 段只保留两个 CSC 场景、
#           文件前缀改为 before3_ / after3_
#   第 7 段（方案 C）只装一个版本：f30bc69 前后的 RegR（.get.obj 已改用 max_times /
#           keep_times）。其中 regr_curve_AB 一格仍按旧接口传 direct_times，报错未计入。
# 汇总结果写在 rpa_cox_optim.csv。


## ==== 第 1 段：方案 A，Cox get_cat 前后对比（ab_run.R <before|after>）

# Usage: Rscript ab_run.R <tag>   (tag = before | after)
tag <- commandArgs(TRUE)[1]
suppressPackageStartupMessages(library(RegR))
pdf(NULL)
base <- readRDS("base_rpa.rds")
set.seed(2026); big <- base[sample.int(nrow(base), 30000, replace = TRUE), ]
cases <- list(
  rpa11_n4387  = list(d = base, cat = "group", adj = "Sex"),
  rpa11_n30000 = list(d = big,  cat = "group", adj = "Sex"),
  sex2_n4387   = list(d = base, cat = "Sex",   adj = "Age")
)
message(sprintf("[%s] RegR loaded from %s", tag, find.package("RegR")))
for (nm in names(cases)) {
  cs <- cases[[nm]]
  sink(nullfile())
  t <- system.time(res <- suppressWarnings(get_cat(cs$d, cat_var = cs$cat, adj_var = cs$adj,
                     surv = TRUE, timepoint = 120)))[["elapsed"]]
  sink()
  saveRDS(res, sprintf("%s_%s.rds", tag, nm))
  message(sprintf("[%s] %-14s get_cat %7.2f s", tag, nm, t))
}

## ---- 第 1 段比较（ab_compare.R）

suppressPackageStartupMessages(library(RegR))
strip <- function(cat) { cat$obj <- lapply(cat$obj, function(o) { o$call <- NULL; o }); cat }
for (nm in c("rpa11_n4387", "rpa11_n30000", "sex2_n4387")) {
  b <- readRDS(sprintf("before_%s.rds", nm))$cat
  a <- readRDS(sprintf("after_%s.rds",  nm))$cat
  cat(sprintf("\n==== %s ====\n", nm))
  for (m in names(b$obj)) {
    pb <- b$obj[[m]]$adj; pa <- a$obj[[m]]$adj
    num <- intersect(c("surv", "se", "ci_lower", "ci_upper"), names(pb))
    cat(sprintf("curve %-6s rows %d vs %d | same time/group keys: %s | max|diff| %s\n", m, nrow(pb), nrow(pa),
        identical(pb[c("time", "group")], pa[c("time", "group")]),
        paste(sprintf("%s=%.1e", num, sapply(num, function(k) max(abs(pb[[k]] - pa[[k]]), na.rm = TRUE))), collapse = " ")))
  }
  for (k in names(b$UM)) cat(sprintf("UM %-12s identical: %s\n", k, identical(b$UM[[k]], a$UM[[k]])))
  if (!is.null(b$Mul)) for (k in names(b$Mul)) cat(sprintf("Mul %-11s identical: %s\n", k, identical(b$Mul[[k]], a$Mul[[k]])))
  ae <- all.equal(strip(b), strip(a))
  cat("all.equal(whole cat, minus obj$call):", if (isTRUE(ae)) "TRUE" else paste(head(ae, 5), collapse = " || "), "\n")
  cb <- names(b$obj$direct$call); ca <- names(a$obj$direct$call)
  cat("obj$direct$call args added:", paste(setdiff(ca, cb), collapse = ", "), "\n")
}

## ==== 第 2 段：方案 B 的取点方式评估（grid_eval.R，已含方案 A）

suppressPackageStartupMessages(library(RegR)); pdf(NULL)
base <- readRDS("base_rpa.rds")
fit_obj <- function(d, times) {
  invisible(gc(reset = TRUE)); sink(nullfile())
  t <- system.time(o <- suppressWarnings(RegR:::.get.obj(d, "group", "Sex", method = "direct",
         times = times, allow_fallback = FALSE)))[["elapsed"]]
  sink(); list(t = t, mb = sum(gc()[, 6]), adj = o$adj)
}
dev <- function(full, grid) {   # drawn line = linear interpolation between points (steps = FALSE)
  out <- sapply(split(full, full$group), function(f) {
    g <- grid[grid$group == f$group[1], ]; f <- f[f$time <= max(g$time), ]
    sapply(c("surv", "ci_lower", "ci_upper"), function(k)
      max(abs(stats::approx(g$time, g[[k]], xout = f$time, ties = "ordered")$y - f[[k]]), na.rm = TRUE))
  })
  apply(out, 1, max)
}
set.seed(2026)
for (n in c(4387, 30000, 50000)) {
  d  <- if (n == nrow(base)) base else base[sample.int(nrow(base), n, replace = TRUE), ]
  et <- sort(unique(d$time[d$DSS == 1]))
  grids <- list(
    even50 = seq(0, max(et), length.out = 50),
    thin50 = c(0, et[unique(round(seq(1, length(et), length.out = 49)))]),
    even25 = seq(0, max(et), length.out = 25)
  )
  full <- fit_obj(d, NULL)
  message(sprintf("n=%6d full   (%3d times)  %6.2f s  peak %6.0f MB", n, length(unique(full$adj$time)), full$t, full$mb))
  for (gn in names(grids)) {
    r <- fit_obj(d, grids[[gn]]); dv <- dev(full$adj, r$adj)
    # exact at shared time points?
    m <- merge(full$adj, r$adj, by = c("time", "group"))
    message(sprintf("n=%6d %-6s (%3d times)  %6.2f s  peak %6.0f MB | max line dev surv=%.4f ci_lo=%.4f ci_hi=%.4f | shared pts=%d exact=%s",
      n, gn, length(grids[[gn]]), r$t, r$mb, dv["surv"], dv["ci_lower"], dv["ci_upper"],
      nrow(m), isTRUE(all.equal(m$surv.x, m$surv.y)) && isTRUE(all.equal(m$ci_lower.x, m$ci_lower.y))))
  }
}

## ---- 第 2 段对比图（grid_plot.R → grid-compare.png）

suppressPackageStartupMessages({library(RegR); library(ggplot2)}); pdf(NULL)
d <- readRDS("base_rpa.rds"); et <- sort(unique(d$time[d$DSS == 1]))
get <- function(times, lab) { sink(nullfile()); o <- suppressWarnings(RegR:::.get.obj(d, "group", "Sex",
  method = "direct", times = times, allow_fallback = FALSE)); sink(); cbind(o$adj, grid = lab) }
x <- rbind(get(NULL, "full (158 pts)"),
           get(c(0, et[unique(round(seq(1, length(et), length.out = 49)))]), "thin50 (event-time quantiles)"),
           get(seq(0, max(et), length.out = 50), "even50 (equal spacing)"))
x$grid <- factor(x$grid, levels = unique(x$grid))
p <- ggplot(x, aes(time, surv, colour = grid, linetype = grid)) +
  geom_ribbon(data = subset(x, grid == "full (158 pts)"), aes(ymin = ci_lower, ymax = ci_upper),
              fill = "grey70", alpha = 0.35, colour = NA, show.legend = FALSE) +
  geom_line(linewidth = 0.5) + facet_wrap(~ group, ncol = 4) +
  scale_colour_manual(values = c("black", "#D62728", "#1F77B4")) +
  scale_linetype_manual(values = c("solid", "dashed", "dotted")) +
  scale_x_continuous(breaks = seq(0, 240, 60)) +
  labs(x = "Months", y = "Adjusted survival (direct, Cox ~ group + Sex)", colour = NULL, linetype = NULL,
       title = "Direct-adjusted curves: full event-time grid vs 50-point grids (n = 4387, grey = full 95% CI)") +
  theme_bw(base_size = 10) + theme(legend.position = "top")
ggsave("grid_compare.png", p, width = 11, height = 7.5, dpi = 150, bg = "white")

## ==== 第 3 段：方案 B，Cox / CSC / FGR get_cat 前后对比（ab2_run.R <before|after>）

# Usage: Rscript ab2_run.R <tag>   (before | after)
tag <- commandArgs(TRUE)[1]
suppressPackageStartupMessages(library(RegR)); pdf(NULL)
if (!file.exists("base2.rds")) {
  data(seer_thyroid_mtc_2026, package = "RegR")
  sink(nullfile()); res <- suppressWarnings(get_rpa(seer_thyroid_mtc_2026, c("Age", "T_stage"),
                                                    adj_var = "Sex", surv = TRUE)); sink()
  b <- as.data.frame(res$dat)[, c("time", "DSS", "event", "status", "group", "Sex", "Age")]
  saveRDS(b[stats::complete.cases(b), ], "base2.rds")
}
base <- readRDS("base2.rds")
set.seed(2026); big <- base[sample.int(nrow(base), 30000, replace = TRUE), ]
cases <- list(
  cox_n4387     = list(d = base, surv = TRUE),
  cox_n30000    = list(d = big,  surv = TRUE),
  cif_csc_n4387 = list(d = base, surv = FALSE, cif_args = list(model = "CSC")),
  cif_fgr_n4387 = list(d = base, surv = FALSE)
)
for (nm in names(cases)) {
  cs <- cases[[nm]]
  args <- list(cs$d, cat_var = "group", adj_var = "Sex", surv = cs$surv, timepoint = 120)
  if (!is.null(cs$cif_args)) args$cif_args <- cs$cif_args
  sink(nullfile()); set.seed(11)
  t <- system.time(res <- suppressWarnings(do.call(get_cat, args)))[["elapsed"]]
  sink()
  saveRDS(res, sprintf("%s2_%s.rds", tag, nm))
  message(sprintf("[%s] %-14s get_cat %7.2f s  direct pts=%d", tag, nm, t,
                  length(unique(res$cat$obj$direct$adj$time))))
}

## ---- 第 3 段比较（ab2_compare.R）

for (nm in c("cox_n4387", "cox_n30000", "cif_csc_n4387", "cif_fgr_n4387")) {
  b <- readRDS(sprintf("before2_%s.rds", nm))$cat; a <- readRDS(sprintf("after2_%s.rds", nm))$cat
  val <- intersect(c("surv", "cif"), names(b$obj$direct$adj))
  cols <- intersect(c(val, "se", "ci_lower", "ci_upper"), names(b$obj$direct$adj))
  fb <- b$obj$direct$adj; fa <- a$obj$direct$adj
  m <- merge(fb, fa, by = c("time", "group"))
  exact <- sapply(cols, function(k) max(abs(m[[paste0(k, ".x")]] - m[[paste0(k, ".y")]]), na.rm = TRUE))
  line <- sapply(cols[cols != "se"], function(k) max(unlist(lapply(split(fb, fb$group), function(f) {
    g <- fa[fa$group == f$group[1], ]; f <- f[f$time <= max(g$time), ]
    abs(stats::approx(g$time, g[[k]], xout = f$time, ties = "ordered")$y - f[[k]])
  })), na.rm = TRUE))
  um <- all(mapply(identical, b$UM, a$UM))
  cat(sprintf("%-14s pts %3d -> %2d | UM tables identical=%s | unadj curve identical=%s\n", nm,
      length(unique(fb$time)), length(unique(fa$time)), um, identical(b$obj$unadj$adj, a$obj$unadj$adj)))
  cat(sprintf("               shared pts max|diff|: %s\n", paste(sprintf("%s=%.1e", names(exact), exact), collapse = " ")))
  cat(sprintf("               drawn-line max dev   : %s\n", paste(sprintf("%s=%.4f", names(line), line), collapse = " ")))
}

## ==== 第 4 段：方案 A 用于 CSC，直接调 adjustedcif()（csc_probe.R）

suppressPackageStartupMessages({library(survival); library(prodlim)})
d <- readRDS("base2.rds"); lv <- levels(d$group)
cd <- d[, c("time", "event", "group", "Sex")]
fit <- riskRegression::CSC(Hist(time, event) ~ group + Sex, data = cd); fit$call$data <- cd
et <- sort(unique(d$time[d$event == 1]))
grids <- list(full = NULL, grid50 = sort(unique(c(0, et[unique(round(seq(1, length(et), length.out = 48)))], 120))))
go <- function(times, ...) { invisible(gc(reset = TRUE))
  t <- system.time(o <- adjustedCurves::adjustedcif(d, variable = "group", ev_time = "time", event = "event",
         cause = 1, method = "direct", outcome_model = fit, conf_int = TRUE, times = times, ...))[["elapsed"]]
  list(t = t, mb = sum(gc()[, 6]), adj = o$adj[order(o$adj$group, o$adj$time), ]) }
for (g in names(grids)) {
  a <- go(grids[[g]]); b <- go(grids[[g]], allContrasts = rbind(lv[1], lv[-1]))
  k <- c("cif", "se", "ci_lower", "ci_upper")
  message(sprintf("CSC %-6s all 55 pairs %6.2f s %5.0f MB | ref-vs-each %6.2f s %5.0f MB | rows %d/%d | max|diff| %.1e",
    g, a$t, a$mb, b$t, b$mb, nrow(a$adj), nrow(b$adj),
    max(abs(as.matrix(a$adj[k]) - as.matrix(b$adj[k])), na.rm = TRUE)))
}

## ==== 第 6 段：n = 30000 的 CSC get_cat 各步骤耗时（csc_parts.R）

suppressPackageStartupMessages(library(RegR)); pdf(NULL)
base <- readRDS("base2.rds"); set.seed(2026); d <- base[sample.int(nrow(base), 30000, replace = TRUE), ]
et <- sort(unique(d$time[d$event == 1]))
grid <- sort(unique(c(0, et[unique(round(seq(1, length(et), length.out = 48)))], 120)))
csc <- list(model = "CSC")
cells <- list(
  curve_AJ_unadj   = function() RegR:::.get.obj(d, "group", "Sex", method = "unadj", times = NULL, surv = FALSE, allow_fallback = FALSE),
  curve_CSC_direct = function() RegR:::.get.obj(d, "group", "Sex", method = "direct", times = NULL, surv = FALSE, allow_fallback = FALSE, cif_args = csc, direct_times = grid),
  HR_crr_unadj     = function() RegR:::.get.UM.haz(d, "group", adj_var = "Sex", surv = FALSE, method = "unadj"),
  HR_crr_direct    = function() RegR:::.get.UM.haz(d, "group", adj_var = "Sex", surv = FALSE, method = "direct"),
  CIF120_unadj     = function() RegR:::.get.UM.sur(d, "group", adj_var = "Sex", surv = FALSE, method = "unadj", time = 120, cif_args = csc),
  CIF120_CSC       = function() RegR:::.get.UM.sur(d, "group", adj_var = "Sex", surv = FALSE, method = "direct", time = 120, cif_args = csc)
)
for (nm in names(cells)) {
  sink(nullfile()); t <- system.time(r <- tryCatch({ cells[[nm]](); "ok" }, error = function(e) conditionMessage(e)))[["elapsed"]]; sink()
  message(sprintf("n=30000 %-16s %7.2f s  %s", nm, t, r))
}

## ==== 第 7 段：方案 C，不求置信区间的调整曲线（c_eval.R，已含 A + B）

# Strategy C (no CI band on direct curves) on top of A + B, Windows R, installed RegR HEAD
suppressPackageStartupMessages({ library(RegR); library(survival); library(prodlim) }); pdf(NULL)
base <- readRDS("base2.rds"); lv <- levels(base$group); ref <- rbind(lv[1], lv[-1])
cat("RegR", as.character(packageVersion("RegR")), "| has direct_times:",
    "direct_times" %in% names(formals(RegR:::.get.obj)), "\n", file = stderr())
grid_of <- function(d, ev) { et <- sort(unique(d$time[ev == 1]))
  sort(unique(c(0, et[unique(round(seq(1, length(et), length.out = 48)))], 120))) }
tm <- function(expr) { invisible(gc(reset = TRUE)); sink(nullfile())
  t <- system.time(v <- tryCatch(force(expr), error = function(e) e))[["elapsed"]]; sink()
  list(t = t, mb = sum(gc()[, 6]), v = v) }
out <- list(); add <- function(...) { out[[length(out) + 1]] <<- data.frame(...)
  r <- out[[length(out)]]; message(sprintf("%-4s n=%6d %-22s %8.2f s %7.0f MB %s", r$model, r$n, r$cell, r$sec, r$peak_mb, r$note)) }
set.seed(2026)
for (n in c(4387, 30000, 100000, 200000)) {
  d <- if (n == nrow(base)) base else base[sample.int(nrow(base), n, replace = TRUE), ]
  g <- grid_of(d, d$DSS)
  fit <- coxph(Surv(time, DSS) ~ group + Sex, data = d, x = TRUE)
  as <- function(...) adjustedCurves::adjustedsurv(d, variable = "group", ev_time = "time", event = "DSS",
                                                   method = "direct", outcome_model = fit, ...)
  r1 <- tm(as(conf_int = TRUE,  times = g, allContrasts = ref))
  add(model = "cox", n = n, cell = "curve_AB_CI", sec = r1$t, peak_mb = r1$mb, note = "")
  r2 <- tm(as(conf_int = FALSE, times = g))
  same <- max(abs(r1$v$adj$surv[order(r1$v$adj$group, r1$v$adj$time)] - r2$v$adj$surv[order(r2$v$adj$group, r2$v$adj$time)]))
  add(model = "cox", n = n, cell = "curve_BC_noCI", sec = r2$t, peak_mb = r2$mb, note = sprintf("surv max|diff| vs CI = %.1e", same))
  r3 <- tm(as(conf_int = FALSE, times = NULL))
  add(model = "cox", n = n, cell = "curve_C_noCI_full", sec = r3$t, peak_mb = r3$mb, note = sprintf("%d times", length(unique(r3$v$adj$time))))
  r4 <- tm(RegR:::.get.obj(d, "group", "Sex", method = "direct", times = NULL, allow_fallback = FALSE, direct_times = g))
  add(model = "cox", n = n, cell = "regr_curve_AB", sec = r4$t, peak_mb = r4$mb, note = "RegR .get.obj incl. diagnostic plot")
  r5 <- tm(RegR:::.get.UM.sur(d, "group", adj_var = "Sex", method = "direct", time = 120))
  add(model = "cox", n = n, cell = "SP120_direct", sec = r5$t, peak_mb = r5$mb, note = "needs CI, C does not apply")
  r6 <- tm(suppressWarnings(get_cat(d, cat_var = "group", adj_var = "Sex", surv = TRUE, timepoint = 120)))
  add(model = "cox", n = n, cell = "get_cat_total_AB", sec = r6$t, peak_mb = r6$mb, note = if (inherits(r6$v, "error")) conditionMessage(r6$v) else "")
  if (n %in% c(30000, 100000)) {
    cd <- d[, c("time", "event", "group", "Sex")]
    cfit <- riskRegression::CSC(Hist(time, event) ~ group + Sex, data = cd); cfit$call$data <- cd
    gc_ <- grid_of(d, d$event)
    ac <- function(...) adjustedCurves::adjustedcif(d, variable = "group", ev_time = "time", event = "event",
                                                    cause = 1, method = "direct", outcome_model = cfit, ...)
    c1 <- tm(ac(conf_int = TRUE,  times = gc_, allContrasts = ref))
    add(model = "csc", n = n, cell = "curve_AB_CI", sec = c1$t, peak_mb = c1$mb, note = "")
    c2 <- tm(ac(conf_int = FALSE, times = gc_))
    add(model = "csc", n = n, cell = "curve_BC_noCI", sec = c2$t, peak_mb = c2$mb, note = "")
  }
  write.csv(do.call(rbind, out), "c_eval.csv", row.names = FALSE)
}
