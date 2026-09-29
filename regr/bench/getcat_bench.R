# get_cat(surv = FALSE): cif_args FGR vs CSC across sample sizes (WSL Rscript).
# Writes getcat_timing.csv, getcat_curves.csv, getcat_mul.csv.
suppressMessages(library(RegR))
pdf(NULL)
d0 <- as.data.frame(RegR::seer_thyroid_mtc_2026)
ns <- c(500, 1000, 2000, 4387, 8774, 17548, 35096)
cat_var <- "Sex"; adj_var <- c("Age", "Race", "M")
quiet <- function(expr) invisible(suppressWarnings(suppressMessages(capture.output(expr))))
make_data <- function(n) {  # same subsamples as bench.R
  set.seed(20260929 + n)
  if (n <= nrow(d0)) d0[sample(nrow(d0), n), ] else d0[sample(nrow(d0), n, replace = TRUE), ]
}
append_csv <- function(x, f) write.table(x, f, sep = ",", row.names = FALSE,
                                         append = file.exists(f), col.names = !file.exists(f))
for (f in c("getcat_timing.csv", "getcat_curves.csv", "getcat_mul.csv"))
  if (file.exists(f)) file.remove(f)

# direct CIF curve: point = full-data fit (adj$cif); CI = bootstrap (FGR) or analytic (CSC)
curve_df <- function(o) {
  ci <- if (!is.null(o$boot_adj)) o$boot_adj else o$adj
  m <- merge(o$adj[, c("time", "group", "cif")], ci[, c("time", "group", "ci_lower", "ci_upper")],
             by = c("time", "group"))
  m[order(m$group, m$time), ]
}

quiet(get_cat(make_data(500), cat_var, adj_var, surv = FALSE, cif_args = list(model = "CSC")))  # warm-up
slow <- character()
for (n in ns) {
  d <- make_data(n)
  reps <- if (n <= 4387) 3 else 2
  for (r in seq_len(reps)) for (m in sample(c("FGR", "CSC"))) {
    if (m %in% slow) next
    set.seed(r); res <- NULL
    st <- system.time(quiet(res <- get_cat(d, cat_var, adj_var, surv = FALSE,
                                           cif_args = list(model = m))))
    append_csv(data.frame(n = n, model = m, rep = r, elapsed = st[["elapsed"]],
                          cpu = sum(st[c("user.self", "sys.self", "user.child", "sys.child")], na.rm = TRUE)),
               "getcat_timing.csv")
    cat(sprintf("n=%d %s rep%d %.1fs\n", n, m, r, st[["elapsed"]]))
    if (r == 1) {
      cv <- curve_df(res$cat$obj$direct); cv$n <- n; cv$model <- m
      append_csv(cv, "getcat_curves.csv")
      mu <- as.data.frame(res$cat$Mul$direct)
      mu <- mu[!is.na(mu$estimate), c("time", "estimate", "conf.low", "conf.high", "p_value")]
      mu$n <- n; mu$model <- m
      append_csv(mu, "getcat_mul.csv")
    }
  }
  tt <- read.csv("getcat_timing.csv")
  slow <- unique(c(slow, tt$model[tt$n == n & tt$elapsed > 900]))
}

cat("DONE\n")
