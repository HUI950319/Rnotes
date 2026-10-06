# Timing benchmark for the Rnotes page "MLR：get_shp 提速策略与实测".
#
# Usage:
#   Rscript mlr_shp_20261006_benchmark.R <platform> <version> <library> <out_dir> [cold]
#
# <platform> is "wsl" (Python SHAP, Linux R with the MLR-shap conda env and a
# CUDA GPU) or "win" (engine = "treeshap", Windows R without Python). The MLR
# installed in <library> is used, so the version before the optimisations
# (df0486b) and after them (0d3247c) can be installed side by side outside the
# default library. Every scenario of the platform runs in this one fresh
# process after a warm-up; "cold" instead times a session's first call only.
# Each call uses 10000 training rows, 400 explained rows and interactions.

args <- commandArgs(TRUE)
platform <- args[1]; version <- args[2]; lib <- args[3]; out_dir <- args[4]
cold <- identical(args[5], "cold")
.libPaths(c(lib, .libPaths()))
suppressPackageStartupMessages(library(MLR))
if (platform == "wsl") reticulate::use_condaenv("MLR-shap", required = TRUE)
engine <- if (platform == "wsl") "python" else "treeshap"

# SEER thyroid MTC cohort (RegR), resampled to 10000 rows; in `cont`, age and
# tumour size get a small jitter so each has about 10000 distinct values.
data(seer_thyroid_mtc_2026, package = "RegR")
vars <- c("Age", "T_stage", "N_stage", "Sex", "Sur", "Tum")
src <- na.omit(RegR::seer_thyroid_mtc_2026[, c("time", "DSS", vars)])
set.seed(1)
seer <- src[sample(nrow(src), 10000, replace = TRUE), ]
rownames(seer) <- NULL
cont <- seer
cont$Age <- cont$Age + runif(nrow(cont), -0.5, 0.5)
cont$Tum <- cont$Tum * exp(rnorm(nrow(cont), 0, 0.05))

call_shp <- function(d, args) {
  base <- list(d, vars, Num.sample = nrow(d), exp.sample = 400,
               engine = engine, render_plots = FALSE)
  set.seed(2)
  res <- NULL
  t <- system.time(utils::capture.output(res <- suppressWarnings(
    suppressMessages(do.call(get_shp, utils::modifyList(base, args)))
  )))[["elapsed"]]
  list(t = t, S = res$shp$S)
}

if (cold) {
  r <- call_shp(seer, list(surv = TRUE, render_plots = TRUE))
  utils::write.table(
    data.frame(platform, version, scenario = "cold_surv_rf_plots", rep = 1,
               seconds = round(r$t, 2)),
    file.path(out_dir, "timing_raw.csv"), sep = ",", row.names = FALSE,
    col.names = !file.exists(file.path(out_dir, "timing_raw.csv")),
    append = TRUE
  )
  quit(save = "no")
}

sc <- function(id, data, args, reps) list(id = id, data = data, args = args, reps = reps)
scenarios <- if (platform == "wsl") list(
  sc("gpu_surv_rf",       seer, list(surv = TRUE), 3),
  sc("gpu_surv_rf_plots", seer, list(surv = TRUE, render_plots = TRUE), 3),
  sc("gpu_class_rf",      seer, list(surv = "DSS"), 3),
  sc("gpu_surv_xgb",      seer, list(surv = TRUE, model = "xgboost"), 3),
  sc("gpu_class_xgb",     seer, list(surv = "DSS", model = "xgboost"), 3),
  sc("gpu_class_lgb",     seer, list(surv = "DSS", model = "lightgbm"), 3),
  sc("cpu_surv_rf",       seer, list(surv = TRUE, device = "cpu"), 1),
  sc("cpu_class_rf",      seer, list(surv = "DSS", device = "cpu"), 1),
  sc("cpu_class_xgb",     seer, list(surv = "DSS", model = "xgboost", device = "cpu"), 3),
  sc("gpu_surv_rf_cont",  cont, list(surv = TRUE), 1)
) else list(
  sc("ts_surv_rf",        seer, list(surv = TRUE), 1),
  sc("ts_surv_rf_plots",  seer, list(surv = TRUE, render_plots = TRUE), 1),
  sc("ts_class_rf",       seer, list(surv = "DSS"), 1),
  sc("ts_surv_rf_noint",  seer, list(surv = TRUE, interactions = FALSE), 3),
  sc("ts_surv_xgb",       seer, list(surv = TRUE, model = "xgboost"), 3),
  sc("ts_class_xgb",      seer, list(surv = "DSS", model = "xgboost"), 3),
  sc("ts_class_lgb",      seer, list(surv = "DSS", model = "lightgbm"), 3),
  sc("ts_surv_rf_cont",   cont, list(surv = TRUE), 1)
)

# Warm-up: load the survival and boosting namespaces, Python and the GPU.
invisible(call_shp(seer[1:600, ], list(surv = TRUE, exp.sample = 20)))
invisible(call_shp(seer[1:600, ], list(surv = "DSS", model = "xgboost",
                                       exp.sample = 20)))

rows <- list(); shap <- list()
for (s in scenarios) {
  for (i in seq_len(s$reps)) {
    r <- call_shp(s$data, s$args)
    rows[[length(rows) + 1L]] <- data.frame(
      platform, version, scenario = s$id, rep = i, seconds = round(r$t, 2)
    )
    message(sprintf("%s %s %s rep %d: %.2f s", platform, version, s$id, i, r$t))
  }
  shap[[s$id]] <- r$S
}
f <- file.path(out_dir, "timing_raw.csv")
utils::write.table(do.call(rbind, rows), f, sep = ",", row.names = FALSE,
                   col.names = !file.exists(f), append = TRUE)
saveRDS(shap, file.path(out_dir, sprintf("shap_%s_%s.rds", platform, version)))
