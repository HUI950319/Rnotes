# MLR get_imp() 优化前后计时（2026-10-06）
#
# 用法：Rscript mlr_imp_20261006_benchmark.R [旧版 MLR 所在库]
#   不给参数时计时当前安装的 MLR；给参数时把该库放在 .libPaths() 最前，
#   用来计时装在临时库里的优化前版本（MLR 706de10）。
# 每次调用前 set.seed(1)；图输出到临时 PDF，计入耗时。

args <- commandArgs(TRUE)
if (length(args)) .libPaths(c(args[1], .libPaths()))
suppressMessages(library(MLR))

tm <- function(label, expr) {
  t <- system.time(val <- force(expr))[["elapsed"]]
  cat(sprintf("%-42s %7.2f s\n", label, t))
  invisible(val)
}

data(seer_thyroid_mtc_2026, package = "RegR")
vars <- c("Age", "Sex", "Race", "Grade", "T_stage", "N_stage", "M")
d <- na.omit(RegR::seer_thyroid_mtc_2026[, c("time", "DSS", vars)])
cat("rows:", nrow(d), " events:", sum(d$DSS == 1),
    " MLR:", as.character(packageVersion("MLR")),
    " from:", find.package("MLR"), "\n")

pdf(tempfile(fileext = ".pdf"))
set.seed(1)
r1 <- tm("survival, first call in session",
         suppressWarnings(get_imp(d, vars, surv = TRUE)))
set.seed(1)
r2 <- tm("survival, second call",
         suppressWarnings(get_imp(d, vars, surv = TRUE)))
set.seed(1)
r3 <- tm("classification",
         suppressWarnings(get_imp(d, vars, surv = "DSS")))
dev.off()

cat("mlr3verse loaded:", "mlr3verse" %in% loadedNamespaces(),
    "| torch loaded:", "torch" %in% loadedNamespaces(), "\n")
cat("first == second (seeded):", isTRUE(all.equal(r1, r2)), "\n")
