suppressMessages(library(RegR))
pdf(NULL)
d <- as.data.frame(RegR::seer_thyroid_mtc_2026)
quiet <- function(expr) invisible(suppressWarnings(suppressMessages(capture.output(expr))))
fit <- function(m, tm, ...) { res <- NULL
  quiet(res <- get_eff(d, cat_var = c("Sex","Race","Che","M"), adj_var = c("Age","Sur"),
                       surv = FALSE, time = tm, cif_args = list(model = m), ...)); res }
agree <- list()
for (tm in c(60, 120)) for (m in c("FGR", "CSC")) { set.seed(1); agree[[paste(tm, m)]] <- fit(m, tm) }
for (s in 1:5) { set.seed(100 + s); agree[[paste0("seed", s)]] <- fit("FGR", 120, methods = "direct")$sur_direct }
saveRDS(agree, "agree_results.rds"); cat("DONE\n")
