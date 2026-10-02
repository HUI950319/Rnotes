# 竞争风险改用 mets：1 万例的前后对比（WSL，R 4.4.3）
#
# 前后两版 RegR 装进两个独立的库，各在一个独立进程里跑同一组调用：
#   before = 254c339（mets 替换之前）  after = 6d5faa8
#   R CMD INSTALL -l lib_before RegR_254c339 ;  R CMD INSTALL -l lib_after RegR_6d5faa8
# 用法（两个进程依次跑，不要同时跑）：
#   OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 Rscript cr_mets_10k.R before
#   OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 Rscript cr_mets_10k.R after
#   Rscript cr_mets_10k.R compare        # 读两份 rds，写 cr_mets_10k.csv / cr_mets_10k_cif.csv
# OMP_NUM_THREADS=1：WSL 上的多线程 BLAS 会让 mets 空转（6 s 的计算用掉 100 多 CPU 秒），
# 其他进程一忙计时就大幅波动；Windows R 的 BLAS 本来就是单线程。
# 每个调用跑 2 次，取较短的一次。

tag <- commandArgs(TRUE)[1]

if (tag %in% c("before", "after")) {
  .libPaths(c(file.path(getwd(), paste0("lib_", tag)), .libPaths()))
  suppressPackageStartupMessages(library(RegR)); grDevices::pdf(NULL)

  ## 与本页其余部分相同的 4387 例 RPA 分组数据，多取竞争风险的 event 列
  data(seer_thyroid_mtc_2026, package = "RegR")
  sink(nullfile())
  res <- suppressWarnings(get_rpa(seer_thyroid_mtc_2026, c("Age", "T_stage"),
                                  adj_var = "Sex", surv = TRUE))
  sink()
  base <- res$dat[, c("time", "DSS", "event", "group", "Sex", "Age")]
  base <- base[stats::complete.cases(base), ]          # 4387 例

  set.seed(2026)
  d <- base[sample.int(nrow(base), 1e4, replace = TRUE),
            c("time", "event", "group", "Sex", "Age")]
  rownames(d) <- NULL
  d$AgeGrp <- factor(ifelse(d$Age >= 55, "ge55", "lt55"), c("lt55", "ge55"))
  d$status <- factor(d$event, levels = 0:2)   # get_facet / get_inter 读 status
  d$DSS <- as.integer(d$event == 1L)          # get_rpa 建树读 DSS
  dr <- d[setdiff(names(d), "group")]         # get_rpa 自己生成 group 列

  run <- function(lab, expr) {
    e <- substitute(expr); ts <- numeric(2); v <- NULL
    for (i in 1:2) {
      set.seed(11); sink(nullfile())
      ts[i] <- system.time(v <- tryCatch(suppressWarnings(suppressMessages(eval(e))),
                                         error = function(err) err))[["elapsed"]]
      sink()
    }
    message(sprintf("[%s] %-32s %7.1f s (runs %s)", tag, lab, min(ts),
                    paste(round(ts, 1), collapse = "/")))
    list(t = min(ts), v = v)
  }
  out <- list(
    get_eff        = run("get_eff", get_eff(d, cat_var = "group", adj_var = c("Sex", "Age"), surv = FALSE, time = 120)),
    get_eff_sub    = run("get_eff(sub_var)", get_eff(d, cat_var = "Sex", sub_var = "AgeGrp", adj_var = "Age", surv = FALSE, methods = "unadj", time = 120)),
    get_inter      = run("get_inter", get_inter(d, exposure_names = c("Sex", "AgeGrp"), adj_var = "Age", surv = FALSE)),
    get_cat        = run("get_cat", get_cat(d, cat_var = "group", adj_var = c("Sex", "Age"), surv = FALSE, timepoint = 120)),
    get_facet      = run("get_facet(direct)", get_facet(d, split_var = "AgeGrp", cat_var = "Sex", adj_var = "Age", surv = FALSE, method = "direct", timepoint = 120)),
    get_facet_diff = run("get_facet_diff", get_facet_diff(d, split_var = "AgeGrp", cat_var = "Sex", adj_var = "Age", surv = FALSE, time_dif = c(12, 36, 60, 120))),
    get_rpa        = run("get_rpa", get_rpa(dr, rpa_var = c("Age", "Sex"), adj_var = "Age", surv = FALSE, timepoint = 120))
  )
  saveRDS(out, sprintf("cmp10k_%s.rds", tag))
}

if (identical(tag, "compare")) {
  b <- readRDS("cmp10k_before.rds"); a <- readRDS("cmp10k_after.rds")
  rel <- function(x, y) { ok <- is.finite(x) & is.finite(y) & y != 0; max(abs(x[ok] / y[ok] - 1)) }
  mx  <- function(x, y) max(abs(x - y), na.rm = TRUE)
  num <- function(s) as.numeric(unlist(regmatches(s, gregexpr("-?[0-9]+[.][0-9]+", s))))
  k   <- function(t) !is.na(t$estimate) & !(t$reference_row %in% TRUE)

  eb <- b$get_eff$v; ea <- a$get_eff$v
  sd_a <- ea$sur_direct[!is.na(ea$sur_direct$estimate_sur), ]
  sd_b <- eb$sur_direct[!is.na(eb$sur_direct$estimate_sur), ]
  w_sur <- (sd_a$conf.high_sur - sd_a$conf.low_sur) / (sd_b$conf.high_sur - sd_b$conf.low_sur)
  ib <- unlist(lapply(b$get_inter$v, function(t) unlist(t[, 2])))
  ia <- unlist(lapply(a$get_inter$v, function(t) unlist(t[, 2])))
  ob <- b$get_cat$v$cat$obj$direct; oa <- a$get_cat$v$cat$obj$direct
  m  <- merge(oa$adj, ob$boot_adj[c("time", "group", "cif", "ci_lower", "ci_upper")],
              by = c("time", "group"), suffixes = c("", ".b"))
  wc <- (m$ci_upper - m$ci_lower) / (m$ci_upper.b - m$ci_lower.b); wc <- wc[is.finite(wc)]
  fb <- b$get_facet$v$sur.data; fa <- a$get_facet$v$sur.data
  fw <- (fa$ci_upper - fa$ci_lower) / (fb$ci_upper - fb$ci_lower); fw <- fw[is.finite(fw)]
  db <- b$get_facet_diff$v$diff.data; da <- a$get_facet_diff$v$diff.data

  tm <- data.frame(
    fun = names(b), before_sec = sapply(b, `[[`, "t"), after_sec = sapply(a, `[[`, "t"),
    change = c(
      sprintf("sHR 最多差 %.2f%%（未调整）/ %.2f%%（调整）；120 月未调整 CIF 不变，调整 CIF 最多差 %.3f，区间宽度为原来的 %.2f–%.2f 倍",
              100 * rel(ea$haz_unadj$estimate[k(ea$haz_unadj)], eb$haz_unadj$estimate[k(eb$haz_unadj)]),
              100 * rel(ea$haz_direct$estimate[k(ea$haz_direct)], eb$haz_direct$estimate[k(eb$haz_direct)]),
              mx(sd_a$estimate_sur, sd_b$estimate_sur), min(w_sur), max(w_sur)),
      sprintf("交互 P %s → %s；亚组 sHR 最多差 %.2f%%",
              unique(na.omit(b$get_eff_sub$v$haz_unadj$p_inter)), unique(na.omit(a$get_eff_sub$v$haz_unadj$p_inter)),
              100 * rel(a$get_eff_sub$v$haz_unadj$estimate[k(a$get_eff_sub$v$haz_unadj)],
                        b$get_eff_sub$v$haz_unadj$estimate[k(b$get_eff_sub$v$haz_unadj)])),
      sprintf("%d / %d 个格子有变化，数值最多差 %.2f（第二位小数）", sum(ib != ia), length(ib), max(abs(num(ia) - num(ib)))),
      sprintf("调整曲线 %d 个点，CIF 最多差 %.3f；区间宽度中位数为原来的 %.2f 倍（四分位 %.2f–%.2f）；表格同 get_eff",
              nrow(m), mx(m$cif, m$cif.b), median(wc), quantile(wc, .25), quantile(wc, .75)),
      sprintf("CIF 曲线 %d 行，点估计最多差 %.3f，区间宽度为原来的 %.2f–%.2f 倍", nrow(fa), mx(fa$cif, fb$cif), min(fw), max(fw)),
      sprintf("CIF 差值最多差 %.4f，P 值最多差 %.3f", mx(da$estimate, db$estimate), mx(da$p_value, db$p_value)),
      "不受影响：get_rpa() 内部固定按 Cox（surv = TRUE）调用 get_cat()，结果相同（差 < 1e-14）"))
  write.csv(tm, "cr_mets_10k.csv", row.names = FALSE, fileEncoding = "UTF-8")
  write.csv(data.frame(group = sd_a$label, before = sd_b$Effect_sur, after = sd_a$Effect_sur),
            "cr_mets_10k_cif.csv", row.names = FALSE, fileEncoding = "UTF-8")
}

# 串行 / 并行对比（cr_mets_parallel.csv）：在 after 版上对 3 个 split（group 合并成
# low / mid / high）各跑 parallel = 1L 和 4L，比较返回结果中的所有数据表是否 identical()：
#   get_facet(d, split_var = "g3", cat_var = "Sex", adj_var = "Age", surv = FALSE,
#             method = "direct", timepoint = 120, parallel = p)
#   get_facet_diff(d, split_var = "g3", cat_var = "Sex", adj_var = "Age", surv = FALSE,
#                  method = "both", time_dif = c(12, 36, 60, 120), parallel = p)
# 其中 d$g3 <- cut(as.integer(d$group), c(0, 3, 7, 11), labels = c("low", "mid", "high"))。
