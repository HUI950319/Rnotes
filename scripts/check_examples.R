# Parse tutorial blocks; optionally execute current UtilsR examples.
args <- commandArgs(trailingOnly = TRUE)
runtime <- "--runtime" %in% args
paths <- args[args != "--runtime"]
if (length(paths) > 1L) stop("Usage: check_examples.R [root] [--runtime]")
root <- if (length(paths)) normalizePath(paths[[1]]) else normalizePath(".")
files <- list.files(root, pattern = "\\.qmd$", recursive = TRUE, full.names = TRUE)
blocks <- list()
for (path in files) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  starts <- grep("^```(r|\\{r[^}]*\\})[[:space:]]*$", lines)
  for (start in starts) {
    ends <- which(seq_along(lines) > start & grepl("^```[[:space:]]*$", lines))
    if (!length(ends)) stop(path, ": unclosed R block at line ", start)
    end <- ends[[1]]
    code <- paste(lines[seq.int(start + 1L, end - 1L)], collapse = "\n")
    tryCatch(parse(text = code), error = function(e) {
      stop(path, ":", start + 1L, ": ", conditionMessage(e), call. = FALSE)
    })
    blocks[[length(blocks) + 1L]] <- list(path = path, code = code,
      marker = if (start > 1L) lines[[start - 1L]] else "")
  }
}
snippet <- function(page, predicate) {
  candidates <- Filter(function(x) endsWith(x[["path"]], page) && predicate(x), blocks)
  if (length(candidates) != 1L) stop("Expected exactly one smoke example in ", page)
  candidates[[1]][["code"]]
}

# The actual SHAP guide code must retain the >200 distinct-value boundary.
env <- new.env(parent = baseenv())
env[["data"]] <- data.frame(continuous = seq_len(250L),
  boundary = rep_len(seq_len(200L), 250L), category = factor(rep_len(c("a", "b"), 250L)))
env[["vars"]] <- names(env[["data"]])
code <- snippet("mlr/shap-guide.qmd", function(x) grepl("^bin_vars <-", x[["code"]]))
invisible(eval(parse(text = code), envir = env))
stopifnot(identical(env[["bin_vars"]], "continuous"))

# Exercise the published sparse-stratum data setup without fitting heavy models.
env <- new.env(parent = baseenv())
env[["d"]] <- data.frame(Sex = factor(rep(c("Female", "Male"), each = 300L)))
code <- snippet("regr/facet-guide.qmd", function(x) x[["marker"]] == "<!-- facet-refit: setup -->")
eval(parse(text = code), envir = env)
d <- env[["d_sparse"]]
female <- d[["Sex"]] == "Female"
stopifnot(all(d[["Cov1"]][female] == d[["Cov2"]][female]),
          any(d[["Cov1"]][!female] != d[["Cov2"]][!female]),
          !any(d[["Site"]][female] == "C"), any(d[["Site"]][!female] == "C"))

# Execute the two published conversions; fitting is verified locally in RegR.
for (unit in c("days", "years")) {
  env <- new.env(parent = baseenv())
  env[["d"]] <- data.frame(time = c(1, 12, 60, 120))
  prefix <- paste0("d_", unit, " <- d")
  code <- snippet("regr/rpa-guide.qmd", function(x) startsWith(x[["code"]], prefix))
  invisible(eval(parse(text = code)[1:2], envir = env))
  expected <- env[["d"]][["time"]] * if (unit == "days") 365.25 / 12 else 1 / 12
  stopifnot(isTRUE(all.equal(env[[paste0("d_", unit)]][["time"]], expected)))
}
cat("PASS:", length(blocks), "R blocks parsed; SHAP binning, sparse strata and RPA time conversions executed\n")

if (runtime) {
  for (pkg in c("UtilsR", "ggplot2", "patchwork")) {
    if (!requireNamespace(pkg, quietly = TRUE)) stop("Runtime examples require ", pkg)
    library(pkg, character.only = TRUE)
  }

  # Execute the published named-axis Sankey, including its current list API.
  env <- new.env(parent = globalenv())
  setup <- snippet("utilsr/flow-guide.qmd", function(x) startsWith(x[["code"]], "library(UtilsR)"))
  eval(parse(text = setup), envir = env)
  mapped <- snippet("utilsr/flow-guide.qmd", function(x) startsWith(x[["code"]], "p_mapped <-"))
  plot <- eval(parse(text = mapped), envir = env)
  built <- ggplot2::ggplot_build(plot)
  stopifnot(nrow(built[["data"]][[1]]) > 0L,
    all(c("Disease stage", "Treatment", "Response") %in% built[["layout"]][["panel_params"]][[1]][["x"]][["get_labels"]]()))

  # ID-based paired inference must agree with the independently paired t-test.
  env <- new.env(parent = globalenv())
  paired <- snippet("utilsr/format-guide.qmd", function(x) grepl("paired_dat <-", x[["code"]], fixed = TRUE))
  plot <- eval(parse(text = paired), envir = env)
  wide <- reshape(env[["paired_dat"]], idvar = "subject", timevar = "visit", direction = "wide")
  wide <- wide[complete.cases(wide), ]
  expected <- stats::t.test(wide[["score.Before"]], wide[["score.After"]], paired = TRUE)[["p.value"]]
  layers <- ggplot2::ggplot_build(plot)[["data"]]
  actual <- layers[[length(layers)]][["p"]]
  stopifnot(nrow(wide) == 23L, length(actual) > 0L, all(abs(actual - expected) < 1e-5))

  # Named design should place the plots by names rather than list order.
  env <- new.env(parent = globalenv())
  setup <- snippet("utilsr/composition-guide.qmd", function(x) startsWith(x[["code"]], "library(UtilsR)"))
  eval(parse(text = setup), envir = env)
  named <- snippet("utilsr/composition-guide.qmd", function(x) startsWith(x[["code"]], "p_named <-"))
  plot <- eval(parse(text = named), envir = env)
  grob <- patchwork::patchworkGrob(plot)
  stopifnot(inherits(grob, "gtable"),
    identical(plot[[1]][["labels"]][["title"]], "A: scatter"),
    identical(plot[[2]][["labels"]][["title"]], "B: boxplot"),
    identical(plot[[3]][["labels"]][["title"]], "C: histogram"))
  cat("PASS runtime: published Sankey, paired comparison and named flattening examples\n")
}
