args <- commandArgs(TRUE)
root <- normalizePath(args[1], winslash = "/")
dest <- normalizePath(args[2], winslash = "/", mustWork = FALSE)
dir.create(dest, recursive = TRUE, showWarnings = FALSE)
os <- if (.Platform$OS.type == "windows") "windows" else "linux"
lib <- file.path(root, paste0("lib_", os, "_after"))
.libPaths(c(lib, .libPaths()))
rows <- list()
jobs <- expand.grid(model = c("cox", "crr"),
                    fun = c("plt_cat1", "plt_cat2", "plt_cat3"), stringsAsFactors = FALSE)
jobs <- rbind(jobs, data.frame(model = c("cox", "cox", "crr"),
                             fun = c("plt_rpa_km", "plt_score", "plt_score")))
jobs$configuration <- ifelse(jobs$fun == "plt_rpa_km", "18_groups_default_palette",
                              ifelse(jobs$fun == "plt_score", "five_metrics", "11_groups"))
extra <- data.frame(model = c("cox", "crr", "cox"),
                    fun = c("plt_cat2", "plt_cat2", "plt_rpa_km"),
                    configuration = c("binary_Sex", "binary_Sex", "18_groups_extended_palette"))
supplement <- length(args) >= 3L && args[3L] == "supplement"
gallery <- length(args) >= 3L && args[3L] == "gallery"
if (gallery) jobs <- data.frame(model = c("crr", "crr"), fun = c("plt_cat2", "plt_cat3"),
  configuration = c("binary_Sex_gallery", "11_groups_gallery")) else
  if (supplement) jobs <- extra else jobs <- rbind(jobs, extra)
for (model in c("cox", "crr")) {
  input <- file.path(root, paste0("cat_", os, "_after_", model, "_binary.rds"))
  if (!file.exists(input)) callr::r(function(root, model, input) {
    suppressPackageStartupMessages(library(RegR))
    options(mc.cores = 4L)
    grDevices::pdf(NULL)
    d <- readRDS(file.path(root, "data_10000.rds"))
    set.seed(20261002)
    x <- RegR::get_cat(d, cat_var = "Sex", adj_var = "Age", surv = model == "cox",
                       timepoint = 120, time_dif = c(12, 36, 60, 120))
    saveRDS(x, input)
  }, args = list(root, model, input), libpath = c(lib, .libPaths()),
  env = c(callr::rcmd_safe_env(), R_LIBS = lib))
}
for (i in seq_len(nrow(jobs))) {
  model <- jobs$model[i]; fun <- jobs$fun[i]
  configuration <- jobs$configuration[i]
  tag <- if (fun == "plt_score") "latest" else "after"
  lib <- file.path(root, paste0("lib_", os, "_", tag))
  input <- if (fun == "plt_score") file.path(root, paste0("score_", os, "_latest_", model, ".rds")) else
    if (fun == "plt_rpa_km") file.path(root, "rpa_linux_after.rds") else
      file.path(root, paste0("cat_", os, "_after_", model, "_get_cat.rds"))
  if (grepl("^binary_Sex", configuration)) input <- file.path(root, paste0("cat_", os, "_after_", model, "_binary.rds"))
  suffix <- if (gallery) "_gallery" else if (configuration == "binary_Sex") "_binary" else
    if (configuration == "18_groups_extended_palette") "_extended" else ""
  output <- file.path(dest, paste0("readback_", os, "_", model, "_", fun, suffix, ".png"))
  z <- tryCatch(callr::r(function(input, output, fun, configuration) {
    suppressPackageStartupMessages(library(RegR))
    grDevices::pdf(NULL)
    x <- readRDS(input)
    a <- if (fun %in% c("plt_score", "plt_rpa_km")) list(x) else list(cat_lis = x)
    if (fun == "plt_cat1") a$display <- "sur"
    if (fun == "plt_cat3") a$risk_table <- FALSE
    if (configuration == "18_groups_extended_palette")
      a$color <- grDevices::hcl.colors(nlevels(x$dat$group), "Dark3")
    warnings <- character()
    elapsed <- system.time(withCallingHandlers({
      p <- do.call(getExportedValue("RegR", fun), a)
      large <- grepl("_gallery$", configuration)
      grDevices::png(output, width = if (large) 4800 else 1600,
                    height = if (large) 3000 else if (fun == "plt_rpa_km") 3300 else 1150, res = 150)
      print(p)
      grDevices::dev.off()
    }, warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning")
    }))[["elapsed"]]
    stopifnot(file.info(output)$size > 10000)
    list(elapsed = elapsed, class = paste(class(p), collapse = "/"), warnings = paste(unique(warnings), collapse = " | "))
  }, args = list(input, output, fun, configuration), libpath = c(lib, .libPaths()),
  env = c(callr::rcmd_safe_env(), R_LIBS = lib)), error = identity)
  failed <- inherits(z, "error")
  rows[[length(rows) + 1L]] <- data.frame(os = os, model = model, n = 10000L,
    function_name = fun, version = tag, configuration = configuration,
    input_system = if (fun == "plt_rpa_km") "linux" else os,
    status = if (failed) "error" else "ok",
    elapsed = if (failed) NA_real_ else z$elapsed,
    error = if (failed) conditionMessage(z) else "",
    warnings = if (failed) "" else z$warnings,
    class = if (failed) "" else z$class, image = basename(output))
}
outfile <- file.path(root, paste0("plot_readback_", os, ".csv"))
out <- do.call(rbind, rows)
if ((supplement || gallery) && file.exists(outfile)) {
  previous <- read.csv(outfile, stringsAsFactors = FALSE)
  if (!"configuration" %in% names(previous))
    previous$configuration <- ifelse(previous$function_name == "plt_rpa_km", "18_groups_default_palette",
      ifelse(previous$function_name == "plt_score", "five_metrics", "11_groups"))
  previous <- previous[!previous$configuration %in% jobs$configuration, names(out)]
  out <- rbind(previous, out)
}
write.csv(out, outfile,
          row.names = FALSE, fileEncoding = "UTF-8")
# Inspect the installed primary source used by the ordinary curve difference.
writeLines(deparse(adjustedCurves::adjusted_curve_diff),
           file.path(root, paste0("adjusted_curve_diff_", os, ".R")))
writeLines(deparse(getFromNamespace("adjusted_curve_diff.fit", "adjustedCurves")),
           file.path(root, paste0("adjusted_curve_diff_fit_", os, ".R")))
writeLines(deparse(getFromNamespace("difference_function", "adjustedCurves")),
           file.path(root, paste0("curve_difference_function_", os, ".R")))
print(do.call(rbind, rows)[, c("os", "model", "function_name", "status", "elapsed", "error")])
