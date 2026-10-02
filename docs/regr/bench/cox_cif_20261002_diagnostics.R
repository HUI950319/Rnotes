args <- commandArgs(TRUE); root <- normalizePath(args[1], winslash="/")
os <- if (.Platform$OS.type == "windows") "windows" else "linux"
.libPaths(c(file.path(root,paste0("lib_",os,"_after")),.libPaths()))
suppressPackageStartupMessages(library(RegR))
d <- readRDS(file.path(root,"data_5000.rds"))
form <- mets::Event(time,event) ~ group + Sex + Age
a <- mets::cifregFG(form,d,cause=1,cens.code=0)
b <- mets::cifregFG(form,d,cause=1,cens.code=0,control=list(tol=1e-10,iter.max=100))
out <- data.frame(os=os, control=c("default","tol=1e-10,iter.max=100"),
                  n=nrow(d), events=a$nevent, df=length(a$coef),
                  design_rank=c(qr(a$design$x)$rank,qr(b$design$x)$rank),
                  max_gradient=c(max(abs(a$gradient)),max(abs(b$gradient))),
                  rejection_threshold=1e-5*(1+a$nevent),
                  all_finite=c(all(is.finite(c(a$coef,a$se.coef))),all(is.finite(c(b$coef,b$se.coef)))),
                  max_beta_change=max(abs(a$coef-b$coef)), logLik=c(a$ploglik,b$ploglik))
write.csv(out,file.path(root,paste0("gradient_diagnostic_",os,".csv")),row.names=FALSE)
print(out)
e <- new.env(); utils::data("seer_thyroid_mtc_2026",package="RegR",envir=e)
dd <- as.data.frame(e$seer_thyroid_mtc_2026)
set.seed(20261002)
ix <- unlist(lapply(split(seq_len(nrow(dd)),dd$event),sample,size=60L))
dd <- droplevels(dd[ix,]); dd$Age[1] <- NA_real_
set.seed(100)
z <- get_fit_stats(dd,list(a="Age",b="Age"),surv=FALSE,R=3)
A <- z$boot[z$boot$model=="a",c("AIC","BIC","PVE")]
B <- z$boot[z$boot$model=="b",c("AIC","BIC","PVE")]
paired <- data.frame(os=os,max_numeric_diff=max(abs(as.matrix(A)-as.matrix(B))),
                      rownames_identical=identical(rownames(A),rownames(B)))
write.csv(paired,file.path(root,paste0("paired_diagnostic_",os,".csv")),row.names=FALSE)
print(paired)
