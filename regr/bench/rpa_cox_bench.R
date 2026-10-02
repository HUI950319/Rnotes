# RPA 生存路径中 Cox 曲线 / HR / 时点生存率的耗时基准（Windows R 4.4.3）
#
# 用法：
#   Rscript rpa_cox_bench.R timing 4387,8000,15000      # 第 1 部分：计时矩阵
#   BENCH_ONLY=curve_direct,SP_direct Rscript rpa_cox_bench.R timing 30000,50000
#   Rscript rpa_cox_bench.R knobs                       # 第 2 部分：ate() 的两个开关
# 输出写到当前目录：bench_<sizes>.csv；knobs 结果打印到 stderr。

args <- commandArgs(TRUE)
mode <- args[1]
suppressPackageStartupMessages({ library(RegR); library(survival) })
pdf(NULL)  # 吞掉 get_rpa() / .get.obj() 自带的 print(plot(...))

## ---- 0. 基础数据：在完整 4387 例上跑一次 get_rpa()，取 RPA 分组 --------------
base_rds <- "base_rpa.rds"
if (!file.exists(base_rds)) {
  data(seer_thyroid_mtc_2026, package = "RegR")
  sink(nullfile())
  res <- suppressWarnings(get_rpa(seer_thyroid_mtc_2026, c("Age", "T_stage"),
                                  adj_var = "Sex", surv = TRUE))
  sink()
  b <- res$dat[, c("time", "DSS", "group", "Sex", "Age")]
  saveRDS(b[stats::complete.cases(b), ], base_rds)
}
base <- readRDS(base_rds)   # n = 4387，597 个事件，11 个 RPA 组

## ---- 1. 计时矩阵 ---------------------------------------------------------------
if (identical(mode, "timing")) {
  sizes <- as.integer(strsplit(args[2], ",")[[1]])

  timeit <- function(expr) {
    invisible(gc(reset = TRUE))
    t <- system.time(r <- tryCatch({ force(expr); "ok" },
                                   error = function(e) paste("ERR:", conditionMessage(e))))[["elapsed"]]
    list(sec = t, mb = sum(gc()[, 6]), status = r)   # gc() "max used"（MB）
  }
  cox <- function(d) coxph(Surv(time, DSS) ~ group + Sex, data = d, x = TRUE)
  cells <- list(
    # get_cat() 的 cat$obj：整条曲线（times = NULL）
    curve_unadj    = function(d) RegR:::.get.obj(d, "group", "Sex", method = "unadj",  times = NULL, allow_fallback = FALSE),
    curve_direct   = function(d) RegR:::.get.obj(d, "group", "Sex", method = "direct", times = NULL, allow_fallback = FALSE),
    # get_cat() 内部 get_eff() 的 haz 表（HR）
    HR_unadj       = function(d) RegR:::.get.UM.haz(d, "group", adj_var = "Sex", method = "unadj"),
    HR_direct      = function(d) RegR:::.get.UM.haz(d, "group", adj_var = "Sex", method = "direct"),
    # get_cat() 内部 get_eff() 的 sur 表（timepoint = 120 的 S(t) 与 ΔS(t)）
    SP_unadj       = function(d) RegR:::.get.UM.sur(d, "group", adj_var = "Sex", method = "unadj",  time = 120),
    SP_direct      = function(d) RegR:::.get.UM.sur(d, "group", adj_var = "Sex", method = "direct", time = 120),
    # 拆分：只调 adjustedsurv(direct)，不经 RegR 包装、不画图
    as_direct_CI   = function(d) adjustedCurves::adjustedsurv(d, variable = "group", ev_time = "time", event = "DSS",
                                   method = "direct", conf_int = TRUE,  outcome_model = cox(d)),
    as_direct_noCI = function(d) adjustedCurves::adjustedsurv(d, variable = "group", ev_time = "time", event = "DSS",
                                   method = "direct", conf_int = FALSE, outcome_model = cox(d)),
    # 整个 get_cat()（与 get_rpa() 生存路径的调用一致）
    get_cat_total  = function(d) get_cat(d, cat_var = "group", adj_var = "Sex", surv = TRUE,
                                         timepoint = 120, methods_obj = c("unadj", "direct"))
  )
  only <- Sys.getenv("BENCH_ONLY")
  if (nzchar(only)) cells <- cells[strsplit(only, ",")[[1]]]

  out <- list()
  set.seed(2026)
  for (n in sizes) {
    # n = 4387 用原数据；更大的 n 按行有放回重抽样（时间网格不变，最多 157 个事件时间）
    d <- if (n == nrow(base)) base else base[sample.int(nrow(base), n, replace = TRUE), ]
    for (nm in names(cells)) {
      sink(nullfile()); r <- timeit(cells[[nm]](d)); sink()
      message(sprintf("n=%7d  %-14s %8.2f s  peak %7.0f MB  %s", n, nm, r$sec, r$mb, r$status))
      out[[length(out) + 1]] <- data.frame(n = n, cell = nm, sec = r$sec, peak_mb = r$mb, status = r$status)
    }
    write.csv(do.call(rbind, out), sprintf("bench_%s.csv", paste(sizes, collapse = "_")), row.names = FALSE)
  }
}

## ---- 2. riskRegression::ate() 的两个开关 ----------------------------------------
# adjustedsurv(method = "direct") 把 ... 原样转给 ate()，所以 times / allContrasts 都能从外面传进去。
if (identical(mode, "knobs")) {
  go <- function(d, fit, ...) {
    invisible(gc(reset = TRUE))
    t <- system.time(o <- adjustedCurves::adjustedsurv(d, variable = "group", ev_time = "time", event = "DSS",
                       method = "direct", conf_int = TRUE, outcome_model = fit, ...))[["elapsed"]]
    list(t = t, mb = sum(gc()[, 6]), pd = o$adj)
  }
  key <- function(p) p[order(p$group, p$time), c("time", "group", "surv", "se", "ci_lower", "ci_upper")]

  # 2a. 时间网格：全部事件时间 vs 每 6 / 12 个月；顺带试只算 1 对对比
  set.seed(2026)
  for (n in c(8000, 30000)) {
    d <- base[sample.int(nrow(base), n, replace = TRUE), ]; lv <- levels(d$group)
    fit <- coxph(Surv(time, DSS) ~ group + Sex, data = d, x = TRUE)
    for (s in list(list(lab = "all_event_times"),
                   list(lab = "allContrasts_1pair", allContrasts = matrix(lv[1:2], nrow = 2)),
                   list(lab = "times_by_6",  times = seq(0, 240, by = 6)),
                   list(lab = "times_by_12", times = seq(0, 240, by = 12)))) {
      r <- do.call(go, c(list(d = d, fit = fit), s[-1]))
      g1 <- r$pd[r$pd$group == lv[1] & r$pd$time == 120, ]
      message(sprintf("n=%6d %-20s %7.2f s  peak %6.0f MB  rows=%5d  S(120)[g1]=%.4f CI=[%.4f, %.4f]",
                      n, s$lab, r$t, r$mb, nrow(r$pd), g1$surv, g1$ci_lower, g1$ci_upper))
    }
  }

  # 2b. 全部 55 对（默认）vs 参照组对其余各组 10 对：结果是否完全相同
  set.seed(2026)
  d <- base[sample.int(nrow(base), 8000, replace = TRUE), ]; lv <- levels(d$group)
  fit <- coxph(Surv(time, DSS) ~ group + Sex, data = d, x = TRUE)
  a <- go(d, fit)
  v <- go(d, fit, contrasts = lv, allContrasts = rbind(lv[1], lv[-1]))
  A <- key(a$pd); V <- key(v$pd)
  message(sprintf("all pairs %.2f s | ref-vs-each %.2f s | same rows: %s | max|diff| surv=%.1e se=%.1e ci=%.1e",
                  a$t, v$t, identical(A[, 1:2], V[, 1:2]), max(abs(A$surv - V$surv)), max(abs(A$se - V$se)),
                  max(abs(c(A$ci_lower - V$ci_lower, A$ci_upper - V$ci_upper)))))
}
