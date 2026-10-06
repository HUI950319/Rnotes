Sys.setenv(OPENBLAS_NUM_THREADS = "1")
suppressMessages(library(MLR))  # 实测时从固定在所测提交的私有库加载（lib.loc）
cat("MLR from:", find.package("MLR"), "\n")
n   <- as.integer(commandArgs(TRUE)[1])
out <- "bench_vpd_ale.csv"

sim <- function(n) {
  set.seed(42)
  age   <- round(rnorm(n, 60, 10))
  tum   <- round(exp(rnorm(n, log(20), 0.6)))
  sex   <- factor(sample(c("Female", "Male"), n, TRUE))
  stage <- factor(sample(c("T1", "T2", "T3"), n, TRUE, prob = c(.5, .3, .2)))
  lp <- 0.06 * (age - 60) + 0.01 * (tum - 20) + 0.5 * (sex == "Male") +
        0.7 * as.integer(stage)
  ev <- rexp(n, 0.001 * exp(lp)); ce <- runif(n, 24, 240)
  data.frame(time = pmax(1, ceiling(pmin(ev, ce))), DSS = as.integer(ev <= ce),
             Age = age, Tum = tum, Sex = sex, T_stage = stage)
}
q <- function(expr) {
  r <- NULL
  utils::capture.output(r <- suppressMessages(suppressWarnings(expr)))
  r
}
el <- function(expr) system.time(expr)[["elapsed"]]

vars <- c("Age", "Tum", "Sex", "T_stage")
calls <- list(
  "get_vpd(Age)"          = function(e) get_vpd(e, exp_var = "Age"),
  "get_vpd(T_stage)"      = function(e) get_vpd(e, exp_var = "T_stage"),
  "get_vpd(Sex, Age)"     = function(e) get_vpd(e, exp_var = c("Sex", "Age")),
  "get_ale(Age)"          = function(e) get_ale(e, exp_var = "Age"),
  "get_ale(T_stage)"      = function(e) get_ale(e, exp_var = "T_stage"),
  "get_ale(Sex, Age)"     = function(e) get_ale(e, exp_var = c("Sex", "Age")),
  "get_ale2(Age, Tum)"    = function(e) get_ale2(e, exp_var = c("Age", "Tum")),
  "get_ale2(Sex, Age)"    = function(e) get_ale2(e, exp_var = c("Sex", "Age"))
)
models <- list(
  sur_cox = list(surv = 120,   model = "default"),
  sur_rf  = list(surv = 120,   model = "ranger"),
  sur_xgb = list(surv = 120,   model = "xgboost"),
  log_glm = list(surv = "DSS", model = "default"),
  log_rf  = list(surv = "DSS", model = "ranger"),
  log_xgb = list(surv = "DSS", model = "xgboost")
)

w <- sim(400); wl <- w; wl$DSS <- factor(wl$DSS)
for (m in list(list(w, 120), list(wl, "DSS"))) {
  ew <- q(get_exp(m[[1]], vars = vars, surv = m[[2]]))
  for (f in calls) { p <- q(f(ew)); grDevices::pdf(NULL); print(p); grDevices::dev.off() }
}

d <- sim(n); dl <- d; dl$DSS <- factor(dl$DSS)
cat(sprintf("== n = %d | events = %.1f%% | unique event times = %d | cores = %d\n",
            n, 100 * mean(d$DSS), length(unique(d$time[d$DSS == 1])),
            MLR:::.resolve_vpd_cores(NULL, n_rows = n)))
row <- function(model, call, compute, render, note = "") {
  r <- data.frame(n = n, model = model, call = call, compute = round(compute, 2),
                  render = round(render, 2), note = note)
  utils::write.table(r, out, sep = ",", row.names = FALSE,
                     col.names = !file.exists(out), append = file.exists(out))
  cat(sprintf("%-8s %-20s compute %7.2f  render %6.2f %s\n",
              model, call, compute, render, note))
}

for (mn in names(models)) {
  m <- models[[mn]]
  e <- NULL
  t <- el(e <- q(get_exp(if (is.character(m$surv)) dl else d, vars = vars,
                         surv = m$surv, model = m$model)))
  row(mn, "get_exp()", t, NA)
  for (cn in names(calls)) {
    p <- NULL; note <- ""
    tc <- el(p <- tryCatch(q(calls[[cn]](e)), error = function(err) {
      note <<- paste("ERROR:", conditionMessage(err)); NULL
    }))
    tr <- if (is.null(p)) NA else el({ grDevices::pdf(NULL); print(p); grDevices::dev.off() })
    row(mn, cn, tc, tr, note)
    rm(p); invisible(gc())
  }
  rm(e); invisible(gc())
}
cat("FINISHED\n")
