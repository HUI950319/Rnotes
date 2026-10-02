# RegR 2026-10-02: matched, sequential Windows / Linux benchmark.
# Rscript benchmark.R <prepare|pilot|matrix|supplement|late> <benchmark-directory>
# Install git exports 2e56cc6 / 12406e3 into lib_<windows|linux>_<before|after>.
args <- commandArgs(TRUE)
mode <- args[1L]
is_pilot <- grepl("^pilot", mode)
root <- normalizePath(args[2L], winslash = "/", mustWork = TRUE)
os <- if (.Platform$OS.type == "windows") "windows" else "linux"
Sys.setenv(OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1")
options(mc.cores = 4L)
sizes <- c(5000L, 10000L, 30000L, 50000L, 100000L)
versions <- c(before = "2e56cc6", after = "12406e3")
if (mode == "late") versions <- c(latest = "ea06c28")

if (mode == "prepare") {
  .libPaths(c(file.path(root, paste0("lib_", os, "_after")), .libPaths()))
  suppressPackageStartupMessages(library(RegR))
  grDevices::pdf(NULL)
  e <- new.env()
  utils::data("seer_thyroid_mtc_2026", package = "RegR", envir = e)
  d <- as.data.frame(e$seer_thyroid_mtc_2026)
  d$event <- RegR:::.to_event(d$event)
  d$DSS <- as.integer(d$event == 1L)
  keep <- c("time", "DSS", "event", "Age", "Sex", "T_stage")
  d <- droplevels(d[complete.cases(d[keep]) & d$time > 0, keep])
  sink(nullfile())
  tree <- get_rpa(d, rpa_var = c("Age", "T_stage"), adj_var = "Sex",
                  cat_arg = list(curve_args = list(ci = FALSE)))
  sink()
  d <- tree$dat[, c(keep, "group")]
  d$AgeGrp <- factor(ifelse(d$Age >= 55, "ge55", "lt55"), c("lt55", "ge55"))
  d$g3 <- factor(ifelse(d$Age < 45, "lt45", ifelse(d$Age < 65, "45to64", "ge65")),
                 c("lt45", "45to64", "ge65"))
  d$status <- factor(d$event, levels = 0:2)
  saveRDS(d, file.path(root, "base.rds"), version = 2)
  set.seed(20261002)
  idx <- sample.int(nrow(d), max(sizes), replace = TRUE)
  for (n in sizes) {
    dd <- d[idx[seq_len(n)], ]
    rownames(dd) <- NULL
    saveRDS(dd, file.path(root, paste0("data_", n, ".rds")), version = 2)
  }
  print(table(d$group)); print(table(d$event))
  quit(status = 0)
}

cases <- c("fit_hazard", "get_eff", "get_eff_sub", "get_cat", "curve_direct",
           "curve_CSC", "get_cat_no_ci", "get_facet", "get_facet_serial",
           "get_facet_diff", "get_facet_diff_serial", "get_inter", "get_inter_abs",
           "get_eff_cat", "get_score", "get_score_boot", "get_rpa", "get_rpa_mp1_mlr",
           "get_rpa_mp1_rr", "get_rpa_mp2", "get_fit_stats", "get_fit_stats_boot",
           "get_rpa_mp2_raw", "get_fit_stats_simple", "get_fit_stats_simple_boot",
           "get_score_all", "get_score_all_boot")
extra <- c("get_rpa_mp2_raw", "get_fit_stats_simple", "get_fit_stats_simple_boot")
late <- c("get_score", "get_score_boot", "get_score_all", "get_score_all_boot",
          "get_fit_stats", "get_fit_stats_boot", "get_fit_stats_simple", "get_fit_stats_simple_boot")
core <- c("fit_hazard", "get_eff", "get_cat")
after_only <- c("get_cat_no_ci", "get_facet_serial", "get_facet_diff_serial",
                "get_fit_stats", "get_fit_stats_boot", "get_fit_stats_simple", "get_fit_stats_simple_boot")
cox_only <- c("get_rpa", "get_rpa_mp1_mlr", "get_rpa_mp1_rr", "get_rpa_mp2", "get_rpa_mp2_raw")
grid <- expand.grid(case = cases, model = c("cox", "crr"), n = sizes,
                    version = names(versions), stringsAsFactors = FALSE)
grid <- grid[!(grid$case %in% after_only & grid$version == "before") &
               !(grid$case %in% cox_only & grid$model == "crr") &
               !(grid$case == "curve_CSC" & grid$model == "cox"), ]
grid <- grid[if (mode == "supplement") grid$case %in% extra else if (mode == "late")
  grid$case %in% late else !grid$case %in% c(extra,"get_score_all","get_score_all_boot"), ]
if (is_pilot) grid <- grid[grid$n == 5000 & grid$version == "after", ]
only <- Sys.getenv("BENCH_ONLY")
if (nzchar(only)) grid <- grid[grid$case %in% strsplit(only, ",", fixed = TRUE)[[1L]], ]
set.seed(20261002)
grid <- grid[order(grid$n, sample.int(nrow(grid))), ]
write.csv(grid, file.path(root, paste0("planned_", os, "_", mode, ".csv")), row.names = FALSE)

worker <- function(dfile, case, model, version, rep, root, os) {
  future::plan(future::sequential)
  options(mc.cores = 4L, .RegR.parallel_worker = NULL)
  d <- readRDS(dfile)
  sv <- model == "cox"
  adj <- c("Sex", "Age")
  models <- list(full = c("group", "Sex", "Age"), simple = c("Sex", "Age"))
  f <- switch(case,
    fit_hazard = function() RegR:::.get.fit(d, "group", adj_var = adj,
                                            outcome = if (sv) "DSS" else "status"),
    get_eff = function() RegR::get_eff(d, cat_var = "group", adj_var = adj, surv = sv, time = 120),
    get_eff_sub = function() RegR::get_eff(d, cat_var = "Sex", sub_var = "AgeGrp", adj_var = "Age",
                                           surv = sv, time = 120, show_surdiff = FALSE),
    get_cat = function() RegR::get_cat(d, cat_var = "group", adj_var = adj, surv = sv, timepoint = 120),
    get_cat_no_ci = function() RegR::get_cat(d, cat_var = "group", adj_var = adj, surv = sv,
                                             timepoint = 120, curve_args = list(ci = FALSE)),
    curve_direct = function() {
      a <- list(data = d, cat_var = "group", adj_var = adj, method = "direct",
                times = NULL, surv = sv, allow_fallback = FALSE)
      if (version == "after") a <- c(a, list(max_times = 50L, keep_times = 120))
      do.call(RegR:::.get.obj, a)
    },
    curve_CSC = function() {
      a <- list(data = d, cat_var = "group", adj_var = adj, method = "direct", times = NULL,
                surv = FALSE, cif_args = list(model = "CSC"), allow_fallback = FALSE)
      if (version == "after") a <- c(a, list(max_times = 50L, keep_times = 120))
      do.call(RegR:::.get.obj, a)
    },
    get_facet = function() RegR::get_facet(d, split_var = "g3", cat_var = "Sex", adj_var = "Age",
                                           surv = sv, method = "direct", timepoint = 120),
    get_facet_serial = function() RegR::get_facet(d, split_var = "g3", cat_var = "Sex", adj_var = "Age",
                                                  surv = sv, method = "direct", timepoint = 120, parallel = 1L),
    get_facet_diff = function() RegR::get_facet_diff(d, split_var = "g3", cat_var = "Sex", adj_var = "Age",
                                                    surv = sv, method = "both", time_dif = c(12, 36, 60, 120)),
    get_facet_diff_serial = function() RegR::get_facet_diff(d, split_var = "g3", cat_var = "Sex", adj_var = "Age",
                                      surv = sv, method = "both", time_dif = c(12, 36, 60, 120), parallel = 1L),
    get_inter = function() RegR::get_inter(d, exposure_names = c("Sex", "AgeGrp"), adj_var = "Age", surv = sv),
    get_inter_abs = function() RegR::get_inter_abs(d, exposure_names = c("Sex", "AgeGrp"), adj_var = "Age",
                                                   surv = sv, sur_time = 120, n_boot = 50L),
    get_eff_cat = function() RegR::get_eff_cat(d, cat_var = "group", adj_var = adj, surv = sv),
    get_score = function() RegR::get_score(d, vars = list(c("group", "Sex", "Age")), surv = sv,
                                           timepoint = c(60, 120), R = 0L),
    get_score_boot = function() RegR::get_score(d, vars = list(c("group", "Sex", "Age")), surv = sv,
                                                timepoint = c(60, 120), R = 10L),
    get_score_all = function() RegR::get_score(d, vars = list(c("group", "Sex", "Age")), surv = sv,
      timepoint = c(60, 120), R = 0L, metrics = c("AUC", "BS", "AIC", "BIC", "PVE")),
    get_score_all_boot = function() RegR::get_score(d, vars = list(c("group", "Sex", "Age")), surv = sv,
      timepoint = c(60, 120), R = 10L, metrics = c("AUC", "BS", "AIC", "BIC", "PVE")),
    get_rpa = function() RegR::get_rpa(d[setdiff(names(d), "group")], rpa_var = c("Age", "T_stage"),
                                       adj_var = "Sex", surv = TRUE, timepoint = 120),
    get_rpa_mp1_mlr = function() RegR::get_rpa_mp1(d, cat_groups = c("Sex", "T_stage"), R = 10L, show_both = TRUE),
    get_rpa_mp1_rr = function() RegR::get_rpa_mp1(d, cat_groups = c("Sex", "T_stage"), R = 10L,
                                                show_both = TRUE, use_mlr3 = FALSE),
    get_rpa_mp2 = function() RegR::get_rpa_mp2(d, cat_groups = c("Sex", "T_stage"), adj_var = "Age", R = 10L, show_both = TRUE),
    get_rpa_mp2_raw = function() RegR::get_rpa_mp2(d, cat_groups = c("Sex", "T_stage"), adj_var = "Age", R = 0L),
    get_fit_stats = function() RegR::get_fit_stats(d, vars = models, surv = sv),
    get_fit_stats_boot = function() RegR::get_fit_stats(d, vars = models, surv = sv, R = 10L),
    get_fit_stats_simple = function() RegR::get_fit_stats(d, vars = list(full = c("Age", "Sex"), simple = "Age"), surv = sv),
    get_fit_stats_simple_boot = function() RegR::get_fit_stats(d, vars = list(full = c("Age", "Sex"), simple = "Age"), surv = sv, R = 10L))
  warnings <- character()
  set.seed(20261002 + rep)
  gc(reset = TRUE)
  writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%OS6 %z"), file.path(root, paste0("started_", os)))
  sink(nullfile())
  tm <- system.time(value <- tryCatch(withCallingHandlers(f(), warning = function(w) {
    warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning")
  }), error = function(e) e))
  sink()
  peak <- sum(gc()[, 6L])
  if (inherits(value, "error")) return(list(elapsed = tm[["elapsed"]], cpu = sum(tm[1:2]),
    child_cpu = sum(tm[4:5]), heap_peak_mb = peak, status = "error", error = conditionMessage(value),
    warnings = unique(warnings), class = class(value)[1L], numeric = data.frame(), tables = list(), actual_method = ""))
  nums <- list(); tables <- list(); methods <- character()
  emit <- function(x, path) {
    if (!is.data.frame(x)) return()
    x <- as.data.frame(x)
    tables[[path]] <<- x
    if (!nrow(x)) return()
    keycols <- intersect(c("variable", "label", "group", "g3", "model", "method", "level", "measure",
                           "metric", "term", "vars", "time", "times", "scheme", "Scheme"), names(x))
    key <- if (length(keycols)) apply(as.data.frame(lapply(x[keycols], as.character)), 1L, paste, collapse = "|") else as.character(seq_len(nrow(x)))
    key <- make.unique(key)
    for (nm in names(x)[vapply(x, is.numeric, logical(1))]) {
      nums[[length(nums) + 1L]] <<- data.frame(path = path, key = key, field = nm, value = x[[nm]])
    }
    if (".final_method" %in% names(x)) methods <<- c(methods, unique(x$.final_method))
  }
  curve <- function(x, path) {
    if (!inherits(x, c("adjustedsurv", "adjustedcif"))) return()
    a <- if (isTRUE(attr(x, "use_boot")) && is.data.frame(x$boot_adj)) x$boot_adj else x$adj
    if ("cif" %in% names(a)) names(a)[names(a) == "cif"] <- "probability"
    if ("surv" %in% names(a)) names(a)[names(a) == "surv"] <- "probability"
    emit(a, path); methods <<- c(methods, x$method)
  }
  walk <- function(x, path, depth = 0L) {
    if (inherits(x, "flextable")) { emit(x$body$dataset, paste0(path, "/body")); return() }
    if (inherits(x, c("adjustedsurv", "adjustedcif"))) { curve(x, path); return() }
    if (is.data.frame(x)) { emit(x, path); return() }
    if (is.list(x) && depth < 3L) for (nm in setdiff(names(x), c("obj", "fit", "model", "data", "dat", "par",
       "plot", "plots", "plt.sur", "plt.rpa1", "plt.rpa2", "task", "call", "info", "metadata"))) walk(x[[nm]], paste0(path, "/", nm), depth + 1L)
  }
  if (case == "fit_hazard") {
    b <- stats::coef(value); s <- sqrt(diag(stats::vcov(value)))
    emit(data.frame(term = names(b), beta = unname(b), se = unname(s)), "fit")
  } else if (case %in% c("get_cat", "get_cat_no_ci")) {
    for (nm in names(value$cat$obj)) curve(value$cat$obj[[nm]], paste0("curve/", nm))
    walk(value$cat$UM, "UM"); walk(value$cat$Mul, "Mul")
    if (nrow(d) == 10000L && rep == 1L) saveRDS(value, file.path(root, paste0("cat_", os, "_", version, "_", model, "_", case, ".rds")))
  } else if (case == "get_rpa") {
    walk(value$rpa.eff$cat.obj$cat$UM, "UM")
    emit(data.frame(group = names(table(value$dat$group)), count = as.numeric(table(value$dat$group))), "tree_groups")
    if (version == "after" && nrow(d) == 10000L) saveRDS(value,
      file.path(root, paste0("rpa_", os, "_after.rds")))
  } else if (inherits(value, "Score")) {
    for (m in c("AUC", "Brier")) emit(value[[m]]$score, paste0("result/", m, "/score"))
    if (!is.null(value$fit.stats)) {
      emit(value$fit.stats$stats, "result/fit.stats/stats")
      emit(value$fit.stats$boot, "result/fit.stats/boot")
      emit(value$fit.stats$info, "result/fit.stats/info")
    }
    emit(value$AUC.BS.AIC, "result/summary")
    if (case == "get_score_all" && nrow(d) == 10000L) saveRDS(value,
      file.path(root,paste0("score_",os,"_",version,"_",model,".rds")))
  } else {
    walk(value, "result")
    for (a in c("risks", "estimates")) emit(attr(value, a), paste0("result/", a))
  }
  list(elapsed = tm[["elapsed"]], cpu = sum(tm[1:2]), child_cpu = sum(tm[4:5]), heap_peak_mb = peak,
       status = "ok", error = "", warnings = unique(warnings), class = paste(class(value), collapse = "/"),
       numeric = if (length(nums)) do.call(rbind, nums) else data.frame(), tables = tables,
       actual_method = paste(unique(methods), collapse = "/"))
}

sessions <- list()
start_session <- function(tag) {
  lib <- file.path(root, paste0("lib_", os, "_", tag))
  opts <- callr::r_session_options(libpath = c(lib, .libPaths()),
    env = c(callr::rcmd_safe_env(), R_LIBS = lib, OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1"))
  s <- callr::r_session$new(options = opts, wait = TRUE, wait_timeout = 30000L)
  meta <- s$run(function() {
    suppressPackageStartupMessages(library(RegR)); grDevices::pdf(NULL)
    pkgs <- c("RegR", "survival", "mets", "riskRegression", "adjustedCurves", "cmprsk", "tidycmprsk", "mlr3", "mlr3proba", "remss")
    list(regR_path = find.package("RegR"), R = R.version.string, session = capture.output(sessionInfo()),
         versions = sapply(pkgs, function(p) if (requireNamespace(p, quietly = TRUE)) as.character(packageVersion(p)) else "missing"),
         run_formals = lapply(c("get_cat", "get_rpa", "get_inter_abs", "get_score"), function(f) formals(get(f, asNamespace("RegR")))))
  })
  saveRDS(meta, file.path(root, paste0("environment_", os, "_", tag, ".rds")))
  s
}
results_file <- file.path(root, paste0("results_", os, "_", mode, ".rds"))
results <- if (file.exists(results_file)) readRDS(results_file) else list()
limit <- if (is_pilot) 90 else 180
for (i in seq_len(nrow(grid))) {
  g <- grid[i, ]; reps <- if (!is_pilot && g$case %in% core) 3L else 1L
  for (r in seq_len(reps)) {
    id <- paste(g$version, g$model, g$n, g$case, r, sep = "_")
    if (id %in% names(results)) { if (results[[id]]$status == "timeout") break; next }
    tag <- g$version
    if (is.null(sessions[[tag]]) || !sessions[[tag]]$is_alive()) sessions[[tag]] <- start_session(tag)
    s <- sessions[[tag]]
    message(sprintf("START %s %s %s n=%d %s rep=%d", os, tag, g$model, g$n, g$case, r))
    started <- file.path(root, paste0("started_", os))
    if (file.exists(started)) unlink(started)
    s$call(worker, list(file.path(root, paste0("data_", g$n, ".rds")), g$case, g$model, tag, r, root, os))
    wait_start <- Sys.time(); result <- NULL
    repeat {
      if (s$poll_process(500L) == "ready") {
        msg <- s$read()
        if (!is.null(msg) && (msg$code == 200L || msg$code >= 500L)) {
          result <- if (is.null(msg$error)) msg$result else list(status = "error", elapsed = NA_real_, error = conditionMessage(msg$error), warnings = character(), numeric = data.frame())
          break
        }
      }
      elapsed_wait <- as.numeric(difftime(Sys.time(), wait_start, units = "secs"))
      if (file.exists(started)) {
        start_text <- readLines(started, warn = FALSE)
        if (length(start_text)) {
          measured_start <- as.POSIXct(start_text[1L], format = "%Y-%m-%d %H:%M:%OS %z")
          if (!is.na(measured_start)) elapsed_wait <- as.numeric(difftime(Sys.time(), measured_start, units = "secs"))
        }
      }
      if (elapsed_wait > limit) {
        s$kill_tree(); sessions[[tag]] <- NULL
        result <- list(status = "timeout", elapsed = elapsed_wait, error = paste0("hard limit ", limit, " s"),
                       warnings = character(), numeric = data.frame(), cpu = NA_real_, child_cpu = NA_real_, heap_peak_mb = NA_real_, class = "", actual_method = "")
        break
      }
    }
    result <- c(as.list(g), list(os = os, rep = r, commit = versions[[tag]], limit_sec = limit), result)
    results[[id]] <- result
    saveRDS(results, results_file)
    flat <- do.call(rbind, lapply(results, function(z) data.frame(os=z$os, version=z$version, commit=z$commit, model=z$model,
      n=z$n, case=z$case, rep=z$rep, elapsed=z$elapsed, status=z$status, error=z$error, warnings=paste(z$warnings,collapse=" | "),
      cpu=if(is.null(z$cpu)) NA_real_ else z$cpu, child_cpu=if(is.null(z$child_cpu)) NA_real_ else z$child_cpu,
      heap_peak_mb=if(is.null(z$heap_peak_mb)) NA_real_ else z$heap_peak_mb,
      actual_method=if(is.null(z$actual_method)) "" else z$actual_method)))
    write.csv(flat, file.path(root, paste0("timing_", os, "_", mode, ".csv")), row.names=FALSE, fileEncoding="UTF-8")
    message(sprintf("DONE %s %.3f s %s %s", id, result$elapsed, result$status, result$error))
    if (result$status == "timeout") break
  }
}
for (s in sessions) if (!is.null(s) && s$is_alive()) s$close()
writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %z"),
           file.path(root,paste0("complete_",os,"_",mode)))
