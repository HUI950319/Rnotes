# get_facet(surv = FALSE, method = "direct"): cif_args FGR vs CSC x show_surdiff,
# across sample sizes (WSL Rscript). Writes getfacet_timing.csv and getfacet_results.rds.
suppressMessages(library(RegR))
pdf(NULL)
d0 <- as.data.frame(RegR::seer_thyroid_mtc_2026)
ns <- c(500, 1000, 2000, 4387, 8774, 17548, 35096)
quiet <- function(expr) invisible(suppressWarnings(suppressMessages(capture.output(expr))))
make_data <- function(n) {  # same subsamples as bench.R
  set.seed(20260929 + n)
  if (n <= nrow(d0)) d0[sample(nrow(d0), n), ] else d0[sample(nrow(d0), n, replace = TRUE), ]
}
cfgs <- expand.grid(model = c("FGR", "CSC"), show_surdiff = c(TRUE, FALSE), stringsAsFactors = FALSE)
cfgs$key <- paste(cfgs$model, ifelse(cfgs$show_surdiff, "surdiff_TRUE", "surdiff_FALSE"), sep = "_")
run <- function(d, k) {
  cf <- cfgs[cfgs$key == k, ]; res <- NULL; err <- NA_character_
  st <- system.time(quiet(tryCatch(
    res <- get_facet(d, split_var = "age_55", cat_var = "Sex", adj_var = c("Age", "Race", "M"),
                     surv = FALSE, method = "direct", cif_args = list(model = cf$model),
                     show_surdiff = cf$show_surdiff, timepoint = 120),
    error = function(e) err <<- conditionMessage(e))))
  list(res = res, st = st, err = err)
}
out <- "getfacet_timing.csv"; if (file.exists(out)) file.remove(out)
invisible(run(make_data(500), "CSC_surdiff_TRUE"))  # warm-up
keep <- list(); slow <- character()
for (n in ns) {
  d <- make_data(n)
  reps <- if (n <= 4387) 3 else 2
  for (r in seq_len(reps)) for (k in sample(cfgs$key)) {
    if (k %in% slow) next
    set.seed(r); x <- run(d, k)
    row <- data.frame(n = n, cfg = k, rep = r, elapsed = x$st[["elapsed"]],
                      cpu = sum(x$st[c("user.self", "sys.self", "user.child", "sys.child")], na.rm = TRUE),
                      error = x$err)
    write.table(row, out, sep = ",", row.names = FALSE, append = file.exists(out), col.names = !file.exists(out))
    cat(sprintf("n=%d %-18s rep%d %.1fs %s\n", n, k, r, row$elapsed, ifelse(is.na(x$err), "", x$err)))
    if (r == 1 && !is.null(x$res)) keep[[paste(n, k)]] <- list(sur.data = x$res$sur.data, insert.data = x$res$insert.data)
  }
  tt <- read.csv(out)
  slow <- unique(c(slow, tt$cfg[tt$n == n & tt$elapsed > 900]))
  saveRDS(keep, "getfacet_results.rds")
}
cat("DONE\n")
