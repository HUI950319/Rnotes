suppressMessages(library(RegR))
pdf(NULL)
out_csv <- "bench_timing.csv"; if (file.exists(out_csv)) file.remove(out_csv)
d0 <- as.data.frame(RegR::seer_thyroid_mtc_2026)
d0$DSS <- as.numeric(d0$DSS)
ns <- c(500, 1000, 2000, 4387, 8774, 17548, 35096)
cfgs <- list(
  crr_surdiff_FALSE = list(surv = FALSE, show_surdiff = FALSE),
  crr_FGR           = list(surv = FALSE, show_surdiff = TRUE, cif_args = list(model = "FGR")),
  crr_CSC           = list(surv = FALSE, show_surdiff = TRUE, cif_args = list(model = "CSC")),
  cox_surdiff_FALSE = list(surv = TRUE,  show_surdiff = FALSE),
  cox_surdiff_TRUE  = list(surv = TRUE,  show_surdiff = TRUE)
)
quiet <- function(expr) suppressWarnings(suppressMessages(capture.output(r <- expr))) 
call_eff <- function(d, cfg) {
  res <- NULL
  st <- system.time(quiet(res <- do.call(get_eff, c(list(d, cat_var = "Sex",
          adj_var = c("Age", "Race", "M"), time = 120), cfg))))
  list(res = res, st = st)
}
make_data <- function(n) {
  set.seed(20260929 + n)
  if (n <= nrow(d0)) d0[sample(nrow(d0), n), ] else d0[sample(nrow(d0), n, replace = TRUE), ]
}
invisible(call_eff(make_data(500), cfgs$crr_CSC)); invisible(call_eff(make_data(500), cfgs$cox_surdiff_TRUE))  # warm-up
keep <- list(); slow <- character()
for (n in ns) {
  d <- make_data(n)
  reps <- if (n <= 4387) 5 else 3
  for (r in seq_len(reps)) for (nm in sample(names(cfgs))) {
    if (nm %in% slow) next
    set.seed(r)
    x <- call_eff(d, cfgs[[nm]])
    row <- data.frame(n = n, cfg = nm, rep = r, elapsed = x$st[["elapsed"]],
                      cpu = sum(x$st[c("user.self","sys.self","user.child","sys.child")], na.rm = TRUE))
    write.table(row, out_csv, sep = ",", append = file.exists(out_csv), col.names = !file.exists(out_csv), row.names = FALSE)
    cat(sprintf("n=%d %-18s rep%d %.2fs\n", n, nm, r, row$elapsed))
    if (r == 1 && nm %in% c("crr_FGR","crr_CSC")) keep[[paste(n, nm)]] <- x$res
  }
  for (nm in names(cfgs)) { # stop growing a config once it exceeds 10 min
    tt <- read.csv(out_csv); if (any(tt$cfg == nm & tt$n == n & tt$elapsed > 600)) slow <- c(slow, nm)
  }
}
saveRDS(keep, "bench_results.rds")

