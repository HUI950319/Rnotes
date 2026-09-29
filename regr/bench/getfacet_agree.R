# Reads getfacet_results.rds written by getfacet_bench.R; writes the two summary CSVs.
k <- readRDS("getfacet_results.rds")
ns <- c(500, 1000, 2000, 4387, 8774, 17548, 35096)
tb_rows <- list(); cv_rows <- list(); hr_same <- c()
for (n in ns) {
  f <- k[[paste(n, "FGR_surdiff_TRUE")]]; c <- k[[paste(n, "CSC_surdiff_TRUE")]]
  for (i in seq_along(f$insert.data$table_tb)) {
    tf <- f$insert.data$table_tb[[i]]; tc <- c$insert.data$table_tb[[i]]
    hr_same <- c(hr_same, identical(tf$HR, tc$HR) && identical(tf$p_HR, tc$p_HR))
    j <- 2  # Male row (non-reference)
    tb_rows[[length(tb_rows) + 1]] <- data.frame(n = n, stratum = as.character(f$insert.data$strata[i]),
      SP_F_Female = tf$SP[1], SP_C_Female = tc$SP[1], SP_F_Male = tf$SP[j], SP_C_Male = tc$SP[j],
      SD_FGR = tf$SD[j], p_FGR = tf$p_SD[j], SD_CSC = tc$SD[j], p_CSC = tc$p_SD[j], HR = tf$HR[j])
  }
  sf <- as.data.frame(f$sur.data); sc <- as.data.frame(c$sur.data)
  m <- merge(sf[, c("strata", "group", "time", "cif", "ci_lower", "ci_upper")],
             sc[, c("strata", "group", "time", "cif", "ci_lower", "ci_upper")],
             by = c("strata", "group", "time"), suffixes = c(".f", ".c"))
  m <- m[m$time > 0, ]; dd <- abs(m$cif.f - m$cif.c); kk <- m$time >= 12
  cv_rows[[length(cv_rows) + 1]] <- data.frame(n = n, max_diff = max(dd),
    where = sprintf("%s / %s, %d", m$strata[which.max(dd)], m$group[which.max(dd)], m$time[which.max(dd)]),
    width_ratio = mean((m$ci_upper.c - m$ci_lower.c)[kk] / (m$ci_upper.f - m$ci_lower.f)[kk], na.rm = TRUE))
}
cat("HR identical FGR vs CSC in every stratum:", all(hr_same), "\n")
tb <- do.call(rbind, tb_rows); cv <- do.call(rbind, cv_rows)
# same curves with show_surdiff TRUE vs FALSE?
cat("sur.data identical surdiff TRUE/FALSE (CSC, 4387):",
    isTRUE(all.equal(k[["4387 CSC_surdiff_TRUE"]]$sur.data, k[["4387 CSC_surdiff_FALSE"]]$sur.data)), "\n")
write.csv(tb, "getfacet_table.csv", row.names = FALSE); write.csv(cv, "getfacet_curve_agree.csv", row.names = FALSE)
options(width = 220); print(tb, row.names = FALSE); print(cv, row.names = FALSE)
