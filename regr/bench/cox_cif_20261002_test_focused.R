args <- commandArgs(TRUE)
root <- normalizePath(args[1L], winslash = "/")
os <- if (.Platform$OS.type == "windows") "windows" else "linux"
tag <- if (length(args) >= 2L) args[2L] else "after"
suffix <- if (tag == "after") "" else paste0("_", tag)
.libPaths(c(file.path(root, paste0("lib_", os, "_", tag)), .libPaths()))
suppressPackageStartupMessages({library(RegR); library(testthat)})
grDevices::pdf(NULL)
Sys.setenv(OMP_NUM_THREADS="1", OPENBLAS_NUM_THREADS="1", MKL_NUM_THREADS="1")
select <- c(
  "test-get-eff-helpers.R" = "auto-dispatches|fits Fine-Gray|tibble with mets|falls back to tidycmprsk",
  "test-get-obj.R" = "Fine-Gray direct CIF comes|asks ate|50 time points|caps direct|curve_args|direct_contrasts",
  "test-get-inter.R" = "Fine-Gray interaction models are fitted with mets",
  "test-get-inter-abs.R" = "full mets covariance|boot refits and standardises with mets|mets joint CIF|mets covariance reaches|explicit CSC",
  "test-get-facet.R" = "caps direct curves|parallelises CIF strata",
  "test-get-facet-diff.R" = "parallelises CIF strata",
  "test-get-rpa.R" = "cit_adj|mob ignores|5 events|mob_int /|cat_arg",
  "test-get-rpa-mp1.R" = "optimized|RPA optimized",
  "test-get-score.R" = "CRR skips coefficient variance",
  "test-get-fit-stats.R" = ".",
  "test-plot-obj-dif.R" = "plot methods are not registered"
)
if (tag == "latest") select <- c("test-get-score.R" = "^get_score |^get_score_summary|^plt_score", "test-get-fit-stats.R" = ".")
out <- if (file.exists(file.path(root, paste0("focused_results_", os, suffix, ".rds"))))
  readRDS(file.path(root, paste0("focused_results_", os, suffix, ".rds"))) else list()
only <- Sys.getenv("TEST_ONLY")
if (nzchar(only)) select <- select[names(select) %in% strsplit(only, ",", fixed=TRUE)[[1L]]]
inventory <- list()
for (file in names(select)) {
  path <- file.path(root, paste0("src_", tag), "tests", "testthat", file)
  ex <- parse(path, keep.source = TRUE)
  is_test <- vapply(ex, function(x) is.call(x) && identical(x[[1L]], as.name("test_that")), logical(1L))
  title <- vapply(ex, function(x) if (is.call(x) && identical(x[[1L]], as.name("test_that"))) as.character(x[[2L]]) else "", character(1L))
  keep <- !is_test | grepl(select[[file]], title)
  chosen <- title[is_test & keep]
  inventory[[file]] <- data.frame(file=file, test=chosen)
  target <- file.path(root, paste0("focused", suffix, "-", file))
  writeLines(unlist(lapply(ex[keep], deparse, width.cutoff = 110L)), target)
  en <- new.env(parent = asNamespace("RegR"))
  en$local_mocked_bindings <- function(..., .package="RegR", .env=parent.frame())
    testthat::local_mocked_bindings(..., .package=.package, .env=.env)
  utils::data("seer_thyroid_mtc_2026", package = "RegR", envir = en)
  message("CHECK ", os, " ", file, " blocks=", length(chosen))
  res <- testthat::test_file(target, reporter = "summary", env = en, stop_on_failure = FALSE)
  tab <- as.data.frame(res); tab$source_file <- file
  out[[file]] <- tab
  saveRDS(out, file.path(root, paste0("focused_results_", os, suffix, ".rds")))
}
tab <- do.call(rbind, out)
write.csv(tab[setdiff(names(tab), "result")], file.path(root, paste0("focused_tests_", os, suffix, ".csv")), row.names=FALSE)
write.csv(do.call(rbind, inventory), file.path(root, "focused_inventory.csv"), row.names=FALSE)
print(tab[, intersect(c("source_file","test","nb","failed","error","warning","skipped","passed"),names(tab))])
quit(status = if (any(tab$failed > 0L | tab$error)) 1L else 0L)
