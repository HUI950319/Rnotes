# Export aggregate model/curve results only; never export patient rows.
args <- commandArgs(TRUE)
root <- normalizePath(args[1], winslash="/")
dest <- args[2]; dir.create(dest, recursive=TRUE, showWarnings=FALSE)
prefix <- file.path(dest, "cox_cif_20261002_")
raw <- list(); all_results <- list()
manifest <- list()
for (os in c("windows","linux")) {
  for (run_mode in c("matrix", "supplement", "late")) {
    file <- file.path(root,paste0("results_",os,"_",run_mode,".rds"))
    if (!file.exists(file)) next
    all_results[[os]] <- c(all_results[[os]],readRDS(file))
    raw[[paste(os,run_mode,sep="_")]] <- read.csv(file.path(root,paste0("timing_",os,"_",run_mode,".csv")),stringsAsFactors=FALSE)
    plan_file <- file.path(root,paste0("planned_",os,"_",run_mode,".csv"))
    plan <- read.csv(plan_file,stringsAsFactors=FALSE)
    manifest[[length(manifest)+1L]] <- data.frame(os=os,run_mode=run_mode,cells=nrow(plan),
      planned_runs=sum(ifelse(plan$case %in% c("fit_hazard","get_eff","get_cat"),3L,1L)),
      started_at=format(file.info(plan_file)$mtime,"%Y-%m-%d %H:%M:%S %z"),
      checkpoint_at=format(file.info(file)$mtime,"%Y-%m-%d %H:%M:%S %z"))
  }
}
write.csv(do.call(rbind,manifest),paste0(prefix,"run_manifest.csv"),row.names=FALSE,fileEncoding="UTF-8")
timing <- do.call(rbind,raw)
write.csv(timing,paste0(prefix,"timing.csv"),row.names=FALSE,fileEncoding="UTF-8")
keycols <- c("os","version","model","n","case")
groups <- split(timing,interaction(timing[keycols],drop=TRUE))
summary <- do.call(rbind,lapply(groups,function(t) {
  valid <- t$status=="ok"
  data.frame(t[1,keycols], median=if(all(valid)) median(t$elapsed[valid]) else NA_real_,
             min=if(any(valid)) min(t$elapsed[valid]) else NA_real_,
             max=if(any(valid)) max(t$elapsed[valid]) else NA_real_,
             attempted=nrow(t), successful=sum(valid),
             status=if(all(valid)) "ok" else paste(unique(t$status),collapse="/"),
             timeout_lower=if(any(t$status=="timeout")) min(t$elapsed[t$status=="timeout"]) else NA_real_,
             error=paste(unique(t$error[nzchar(t$error)]),collapse=" | "),
             warnings=paste(unique(t$warnings[nzchar(t$warnings)]),collapse=" | "),
             heap_peak_mb=if(any(valid)) max(t$heap_peak_mb[valid],na.rm=TRUE) else NA_real_)
}))
write.csv(summary,paste0(prefix,"summary.csv"),row.names=FALSE,fileEncoding="UTF-8")
numeric_results <- list(); formatted <- list(); classes <- list()
for (os in names(all_results)) for (z in all_results[[os]]) {
  if(z$rep!=1L) next
  id <- data.frame(os=os,version=z$version,model=z$model,n=z$n,case=z$case)
  classes[[length(classes)+1L]] <- data.frame(id,status=z$status,class=if(is.null(z$class)) "" else z$class,
                                             actual_method=if(is.null(z$actual_method)) "" else z$actual_method)
  if(z$status!="ok") next
  # Rebuild keys from retained aggregate tables, including the facet method.
  # This keeps adjusted and unadjusted curves distinct when grids differ.
  for(p in names(z$tables)) {
    tab <- as.data.frame(z$tables[[p]])
    if(!nrow(tab)) next
    keys <- intersect(c("variable", "label", "group", "g3", "model", "method", "methods", "strata",
      "level", "measure", "metric", "term", "vars", "time", "times", "scheme", "Scheme",
      "comparison", "pair"), names(tab))
    key <- if(length(keys)) apply(as.data.frame(lapply(tab[keys],as.character)),1L,paste,collapse="|") else as.character(seq_len(nrow(tab)))
    key <- make.unique(key)
    for(field in names(tab)[vapply(tab,is.numeric,logical(1L))]) {
      numeric_results[[length(numeric_results)+1L]] <- data.frame(id,path=p,key=key,field=field,value=tab[[field]])
    }
  }
  for(p in names(z$tables)) {
    # Curves are fully retained as numeric aggregates, not duplicated as text.
    if(grepl("^curve|sur.data|diff.data|^result/adj",p) ||
       (z$case %in% c("curve_direct", "curve_CSC") && p == "result")) next
    tab <- as.data.frame(z$tables[[p]])
    if(!nrow(tab)) next
    # List columns can contain entire fitted objects and patient rows.
    # Publish scalar aggregate columns only, never their serialized contents.
    fields <- names(tab)[vapply(tab, function(x) is.atomic(x) && is.null(dim(x)), logical(1L))]
    fields <- setdiff(fields, ".obj")
    for(j in fields) {
      values <- vapply(seq_len(nrow(tab)),function(i) paste(as.character(tab[[j]][i]),collapse=";"),character(1L))
      formatted[[length(formatted)+1L]] <- data.frame(id,path=p,row=seq_len(nrow(tab)),field=j,value=values)
    }
  }
}
num <- if(length(numeric_results)) do.call(rbind,numeric_results) else data.frame()
for(os in names(all_results)) write.csv(num[num$os==os,],paste0(prefix,"numeric_",os,".csv"),row.names=FALSE,fileEncoding="UTF-8")
if(length(formatted)) write.csv(do.call(rbind,formatted),paste0(prefix,"tables.csv"),row.names=FALSE,fileEncoding="UTF-8")
write.csv(do.call(rbind,classes),paste0(prefix,"classes.csv"),row.names=FALSE,fileEncoding="UTF-8")
compare <- function(a,b,label) {
  out <- merge(a,b,by=c("path","key","field"),suffixes=c(".a",".b"))
  out <- out[is.finite(out$value.a)&is.finite(out$value.b),]
  if(!nrow(out)) return(NULL)
  sp <- split(out,interaction(out$path,out$field,drop=TRUE))
  do.call(rbind,lapply(sp,function(x) data.frame(label=label,path=x$path[1],field=x$field[1],
    pairs=nrow(x),max_abs=max(abs(x$value.a-x$value.b)),
    max_rel=max(abs(x$value.a-x$value.b)/pmax(abs(x$value.a),1e-8)),
    min_a=min(x$value.a),max_a=max(x$value.a),min_b=min(x$value.b),max_b=max(x$value.b))))
}
agree <- list()
if(nrow(num)) for(os in unique(num$os)) for(model in unique(num$model)) for(n in unique(num$n)) for(case in unique(num$case)) {
  for (pair in list(c("before","after","before_after"),c("after","latest","after_latest"))) {
    a <- num[num$os==os & num$model==model & num$n==n & num$case==case & num$version==pair[1],c("path","key","field","value")]
    b <- num[num$os==os & num$model==model & num$n==n & num$case==case & num$version==pair[2],c("path","key","field","value")]
    if(nrow(a)&&nrow(b)) {
      x <- compare(a,b,pair[3])
      if(!is.null(x)) agree[[length(agree)+1L]] <- cbind(data.frame(os=os,model=model,n=n,case=case),x)
    }
  }
}
if(nrow(num) && all(c("windows","linux") %in% unique(num$os))) for(model in unique(num$model)) for(n in unique(num$n)) for(case in unique(num$case)) for(version in c("after","latest")) {
  a <- num[num$os=="windows" & num$model==model & num$n==n & num$case==case & num$version==version,c("path","key","field","value")]
  b <- num[num$os=="linux" & num$model==model & num$n==n & num$case==case & num$version==version,c("path","key","field","value")]
  if(nrow(a)&&nrow(b)) {
    x <- compare(a,b,if(version=="after") "windows_linux" else "latest_windows_linux")
    if(!is.null(x)) agree[[length(agree)+1L]] <- cbind(data.frame(os="both",model=model,n=n,case=case),x)
  }
}
if(length(agree)) write.csv(do.call(rbind,agree),paste0(prefix,"agreement.csv"),row.names=FALSE,fileEncoding="UTF-8")
tests <- do.call(rbind,lapply(names(all_results),function(os) {
  x <- read.csv(file.path(root,paste0("focused_tests_",os,".csv")))
  x$os <- os; x
}))
write.csv(tests,paste0(prefix,"tests.csv"),row.names=FALSE,fileEncoding="UTF-8")
late_tests <- list()
for(os in names(all_results)) {
  file <- file.path(root,paste0("focused_tests_",os,"_latest.csv"))
  if(file.exists(file)) {
    x <- read.csv(file); x$os <- os
    late_tests[[os]] <- x
  }
}
if(length(late_tests)) write.csv(do.call(rbind,late_tests),paste0(prefix,"latest_tests.csv"),row.names=FALSE,fileEncoding="UTF-8")
plot_tests <- list()
for(os in names(all_results)) {
  file <- file.path(root,paste0("plot_readback_",os,".csv"))
  if(file.exists(file)) plot_tests[[os]] <- read.csv(file)
}
if(length(plot_tests)) write.csv(do.call(rbind,plot_tests),paste0(prefix,"plot_readback.csv"),row.names=FALSE,fileEncoding="UTF-8")
data_summary <- do.call(rbind,lapply(c(5000L,10000L,30000L,50000L,100000L),function(n) {
  d <- readRDS(file.path(root,paste0("data_",n,".rds")))
  data.frame(n=n,censor=sum(d$event==0),target_events=sum(d$event==1),
    competing_events=sum(d$event==2),groups=nlevels(d$group),min_time=min(d$time),max_time=max(d$time))
}))
write.csv(data_summary,paste0(prefix,"data_summary.csv"),row.names=FALSE,fileEncoding="UTF-8")
environ <- list()
for(os in names(all_results)) for(version in c("before","after","latest")) {
  if (!file.exists(file.path(root,paste0("environment_",os,"_",version,".rds")))) next
  e <- readRDS(file.path(root,paste0("environment_",os,"_",version,".rds")))
  environ[[length(environ)+1L]] <- data.frame(os=os,version=version,R=e$R,package=names(e$versions),package_version=unname(e$versions))
  writeLines(e$session,paste0(prefix,"session_",os,"_",version,".txt"))
}
write.csv(do.call(rbind,environ),paste0(prefix,"environment.csv"),row.names=FALSE,fileEncoding="UTF-8")
for(typ in c("gradient","paired")) {
  x <- do.call(rbind,lapply(names(all_results),function(os) read.csv(file.path(root,paste0(typ,"_diagnostic_",os,".csv")))))
  write.csv(x,paste0(prefix,typ,"_diagnostic.csv"),row.names=FALSE,fileEncoding="UTF-8")
}
message("Exported ",nrow(timing)," timing runs, ",nrow(summary)," cells, ",nrow(num)," aggregate numeric values.")
